# Wedbook (Matrimony Agents) — Backend

Express + PostgreSQL API behind both apps: **Wedbook Agent** (agents; code name Mediator) and
**Wedbook Matrimony** (customers; code name Gandharva). Route contract: `docs/SPEC.md` §4 and §9
(§9.18 for agent codes, customer IDs, privacy toggles and the community audience). Business
rules: `CLAUDE.md`.

## Run with Docker (the normal way, and how it runs on the Oracle VM)

```bash
cp .env.example .env      # set DB_PASSWORD and JWT_SECRET (openssl rand -hex 32)
docker compose up -d --build
curl http://localhost:3000/api/health     # {"ok":true}
```

`db/schema.sql` is applied automatically on the **first** start of the `db` container
(it is mounted into `docker-entrypoint-initdb.d`). Later schema changes go in
numbered files under `db/migrations/` and are applied by hand.

## Run without Docker (local development)

Needs a PostgreSQL 16/17 server. With the Postgres binaries on PATH:

```bash
initdb -D ./pgdata -U postgres --auth=trust
pg_ctl -D ./pgdata -o "-p 5433" -w start
createdb -h 127.0.0.1 -p 5433 -U postgres matrimony
psql "postgres://postgres@127.0.0.1:5433/matrimony" -f db/schema.sql
```

Then create `.env.local` (git-ignored):

```
DATABASE_URL=postgres://postgres@127.0.0.1:5433/matrimony
JWT_SECRET=any-long-random-string-for-dev
PUBLIC_BASE_URL=http://localhost:3000
PORT=3000
```

```bash
npm install
npm run dev
```

## Testing

```bash
npm run smoke        # 1525 end-to-end checks (46 steps) against a running API
DATABASE_URL=... npm run test:providers   # 137 checks: Firebase OTP, Fast2SMS, StartMessaging, Razorpay, reviewer login, website
npm run seed:demo    # 2 communities, 3 agents (codes TS… / AP… / KA…), 12 profiles with photos, 6 customers
```

`npm run smoke` asserts every rule in `CLAUDE.md`: community visibility, pending-agent
gating, omitted contact fields, the 15-day approval window, revocation, masked shares and
public pages, share logging, and admin-only access. Point it elsewhere with
`BASE=https://your-domain npm run smoke`.

`npm run test:providers` (SPEC §9.19) starts its own API on port 3101 with
`OTP_PROVIDER=firebase` and `PAYMENT_PROVIDER=razorpay` (plus a second one on 3102 with
`OTP_PROVIDER=fast2sms`), pointed at in-process fakes of Google's ID-token certificates,
Razorpay's REST API and Fast2SMS (needs `openssl` on PATH and a test
database with the schema loaded). It checks ID-token validation (signature, project, issuer,
expiry, freshness, phone number), the send/verify contract, order creation, the checkout
signature, capture, the safety net, the webhook and `refund_due`.

After seeding, log in as `9000000001` / `demo1234` (agent) or `9999999999` /
`ChangeMe@123` (admin — **change this immediately**).

## Environment

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | Postgres connection string (required) |
| `JWT_SECRET` | Token signing secret (required) — generate, never commit |
| `PUBLIC_BASE_URL` | Origin used to build `/p/:token` share links |
| `PORT` | Default 3000 |
| `UPLOADS_DIR` | Photo storage root, default `uploads` |
| `CONTACT_ACCESS_DAYS` | Approval window, default 15 |
| `JWT_EXPIRES_IN` | Token lifetime, default `30d` |
| `BCRYPT_ROUNDS` | Default 10 |
| `ANTHROPIC_API_KEY` | Optional. Enables `POST /profiles/parse` (AI import). Unset → 503 and the app hides the button |
| `CLAUDE_MODEL` | Extraction model, default `claude-opus-5`; `claude-haiku-4-5` is ~5× cheaper |

## Migrations

`db/schema.sql` runs once on the first `db` container start. Later changes live in
`db/migrations/NNN_*.sql`, are idempotent, and are applied by hand:

```bash
docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/001_subcastes.sql
docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < db/migrations/002_profile_fields_password_reset.sql
```

| Migration | What it adds |
|---|---|
| `001_subcastes.sql` | `subcastes` master + `profiles.subcaste_id` |
| `002_profile_fields_password_reset.sql` | `complexions` + `countries` masters; gothram, work place, education/profession details, weight, complexion, NRI (country + place), father/mother name + phone on `profiles`; `agents.must_change_password` + `password_reset_requests` for the forgot-password flow |
| `003` … `010` | see `db/migrations/README.md` — `010_wedbook_codes_privacy.sql` is the newest (states, agent codes, profile IDs, privacy toggles, community audience) |

Keep `schema.sql` in sync so a fresh install and a migrated one match. `deploy/update.sh`
re-runs every migration on each deploy, which is why they must stay idempotent.

## Layout

```
src/
  server.js            route mounting, rate limiting, expiry job
  lib/       config, db, auth, errors, validation, photos, card, pdf, profiles,
             profileQuery, profileWrite, customers, payments, otp, push,
             codes (agent codes + profile IDs), privacy (the toggles)
  middleware/          requireAuth / requireActive / requireAdmin, requireCustomer, error handler
  routes/    auth, masters, profiles, photos, contactRequests, holdRequests, share,
             publicPage, shortlists, notifications, me, admin, clients,
             customerAuth, customerApp, customerNotifications, registration, push
db/schema.sql          tables + seed data (27 nakshatrams, 12 rasis, …)
db/migrations/         numbered follow-up changes
test/                  smoke.mjs, providers.mjs, seed-demo.mjs
uploads/               profile photos (git-ignored, Docker volume)
```

## Notes

- Photos are resized to max 1280px / JPEG 80% on upload and served only through
  authenticated routes. Public pages and downloads get watermarked copies.
- The Docker image installs `font-dejavu` — `sharp` renders the watermark and
  share-card text from SVG, which needs real fonts present.
- `docker-compose.dev.yml` publishes the database port for local development.
  Never use it on the server.
