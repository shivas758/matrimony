# Mediator (Matrimony Agents) — Backend

Express + PostgreSQL API. Route contract: `docs/SPEC.md` §4. Business rules: `CLAUDE.md`.

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
npm run smoke        # 248 end-to-end checks against a running API
npm run seed:demo    # 2 communities, 3 agents, 12 profiles with photos
```

`npm run smoke` asserts every rule in `CLAUDE.md`: community visibility, pending-agent
gating, omitted contact fields, the 15-day approval window, revocation, masked shares and
public pages, share logging, and admin-only access. Point it elsewhere with
`BASE=https://your-domain npm run smoke`.

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

Keep `schema.sql` in sync so a fresh install and a migrated one match.

## Layout

```
src/
  server.js            route mounting, rate limiting, expiry job
  lib/       config, db, auth, errors, validation, photos, card, profiles
  middleware/          requireAuth / requireActive / requireAdmin, error handler
  routes/    auth, masters, profiles, photos, contactRequests, share,
             publicPage, shortlists, notifications, me, admin
db/schema.sql          tables + seed data (27 nakshatrams, 12 rasis, …)
db/migrations/         numbered follow-up changes
test/                  smoke.mjs, seed-demo.mjs
uploads/               profile photos (git-ignored, Docker volume)
```

## Notes

- Photos are resized to max 1280px / JPEG 80% on upload and served only through
  authenticated routes. Public pages and downloads get watermarked copies.
- The Docker image installs `font-dejavu` — `sharp` renders the watermark and
  share-card text from SVG, which needs real fonts present.
- `docker-compose.dev.yml` publishes the database port for local development.
  Never use it on the server.
