# Mediator (Matrimony Agents) App

**Mediator — Matrimony Partners.** Private platform for marriage bureau agents: organised profiles, filters, controlled WhatsApp sharing (link, PDF bio-data or photo card), and protected contact details. Replaces unstructured WhatsApp forwarding.

**MILI Matrimony** (formerly *Gandharva*; same package, installs update in place). The companion app for the agents' customers: sign up with just phone + OTP and browse as a guest (photo, age, job, caste, package), then choose an agent, register one profile and pay the ₹150 registration fee (mock checkout for now) to open profiles in the agent's communities, mark *interested*, see a profile's on-request details once the other side's agent accepts, and switch agents with approval. Agents manage their customers under **Clients** in Mediator and can also send a public registration-form link.

**Stack:** Flutter (Android) · Node.js + Express · PostgreSQL · Docker · Oracle Cloud Free Tier

## Status

| Part | State |
|---|---|
| Backend API | Complete — every route in `docs/SPEC.md` §4 incl. subcastes, AI import, NRI/gothram/complexion fields, protected native place + parents, and the admin-driven forgot-password flow — 248 end-to-end checks passing |
| Flutter app (Mediator) | Complete — all screens in `docs/SPEC.md` §5 and §9.11: OTP signup, Clients tab (approve customers, interests, transfers, registration link), the registration-form fields, the "on request" field split, admin customers |
| Flutter app (MILI) | Complete — `docs/SPEC.md` §9.11 – §9.17: OTP login, guest browsing, get-started checklist (agent → profile → ₹150 mock payment → approval), one profile per customer (a paid one is deleted with the agent's approval), photo editor + camera, browse + filters (guests too), interests on behalf of a profile, change agent (`customer_app/`) |
| Deployment | **Live** on an Oracle Always Free VM behind Caddy/HTTPS, nightly backups on cron — `deploy/ORACLE_SETUP.md` is the runbook |

## Run it locally

**1. Backend** (see `backend/README.md` for the non-Docker path):

```bash
cd backend
cp .env.example .env      # set DB_PASSWORD and JWT_SECRET
docker compose up -d --build
curl http://localhost:3000/api/health     # {"ok":true}
```

**2. Verify the business rules:**

```bash
cd backend && npm install && npm run smoke
```

**3. Demo data to develop against:**

```bash
cd backend && npm run seed:demo
```

**4. App** (Android emulator):

```bash
cd app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

**5. APKs:**

```bash
cd app && flutter build apk --release --target-platform android-arm,android-arm64 --dart-define=API_BASE_URL=https://your-domain.example.in
cd customer_app && flutter build apk --release --target-platform android-arm,android-arm64 --dart-define=API_BASE_URL=https://your-domain.example.in
```

Send `app/build/app/outputs/flutter-apk/app-release.apk` (Mediator, ~34 MB) to agents and
`customer_app/build/app/outputs/flutter-apk/app-release.apk` (MILI) to customers over WhatsApp.

**6. Customer app on the emulator:** `cd customer_app && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000`

## Logins

| Who | Phone | Password |
|---|---|---|
| Admin | `9999999999` | `ChangeMe@123` — **change it on first login** |
| Demo agents (after `npm run seed:demo`) | `9000000001` … `9000000003` | `demo1234` |
| Any OTP while `OTP_PROVIDER=mock` (default) | — | code `123456` |
| Registration fee while `PAYMENT_PROVIDER=mock` (default) | — | *Pay ₹150* succeeds, *Simulate failure* fails — nothing is charged |

Replace the placeholder communities (Community A/B/C) with your real ones from
**More → Admin → Master lists**.

## What's here

- `CLAUDE.md` — rules and working instructions
- `docs/SPEC.md` — full specification: schema, permissions, API, screens
- `backend/` — Express API, Docker Compose, SQL schema + seed data, smoke test
- `app/` — Flutter app for agents (auth, list/filters, detail, add/edit, requests, clients, sharing, shortlists, admin)
- `customer_app/` — Flutter app for customers (MILI, formerly Gandharva)
- `deploy/ORACLE_SETUP.md` — copy-paste Oracle VM setup with HTTPS and backups

## Key business rules

- Agents see only profiles in their selected communities; new agents need admin activation.
- Anyone can share/download profiles, but shares are always masked (no contacts, no uploader identity) and logged.
- The "on request" details (contacts, parents, native and birth place, work place, siblings, family, property) unlock only via uploader/admin approval — a contact request for agents, an accepted *interest* for customers — valid 15 days, revocable.
- A customer belongs to one agent, needs that agent's approval, and can change agent only with the current agent's approval.

`backend/test/smoke.mjs` asserts each of these against a running API.
