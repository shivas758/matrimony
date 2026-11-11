# Wedbook (Matrimony Agents)

**Wedbook Agent** (called *Mediator* until v2.7; same package, installs update in place). Private platform for marriage bureau agents: organised profiles, filters, controlled WhatsApp sharing (link, PDF bio-data or photo card), and protected contact details. Replaces unstructured WhatsApp forwarding. Every agent has a permanent **agent code** from their State (`KA1A`, `KA1B` …) and every profile a permanent **ID** (`GN-KA1A-A001`).

**Wedbook Matrimony** (formerly *MILI* / *Gandharva*; same package, installs update in place). The companion app for the agents' customers: sign up with just phone + OTP and browse as a guest (photo, age, job, caste, package), then choose an agent, register one profile and pay the ₹150 registration fee (Razorpay Checkout — UPI, cards, net banking — or a mock checkout until the keys are set) to open profiles in the agent's communities, mark *interested*, see a profile's on-request details once the other side's agent accepts, and switch agents with approval. Each family chooses with **privacy toggles** which details others see before approval (only the main photo, age and gender are always shown) and which communities their profile is shown to. Agents manage their customers under **Clients** in Wedbook Agent and can also send a public registration-form link. Profile forms are four steps everywhere: Personal → Professional → Horoscope → Family & contact.

**Stack:** Flutter (Android) · Node.js + Express · PostgreSQL · Docker · Oracle Cloud Free Tier

## Status

| Part | State |
|---|---|
| Backend API | Complete — every route in `docs/SPEC.md` §4 incl. subcastes, AI import, NRI/gothram/complexion fields, protected native place + parents, the admin-driven forgot-password flow, customers / OTP / interests / payments, and (§9.18) agent codes, profile IDs, privacy toggles and the community audience, plus (§9.19) real OTP through StartMessaging (Fast2SMS / Firebase phone auth as alternatives) and Razorpay (capture, safety net, webhook) — 1525 end-to-end checks + 137 provider checks passing |
| Flutter app (Wedbook Agent) | Complete — all screens in `docs/SPEC.md` §5, §9.11 and §9.18 (State + agent code, profile IDs, four-step form with the privacy card): OTP signup, Clients tab (approve customers, interests, transfers, registration link), the registration-form fields, the "on request" field split, admin customers |
| Flutter app (Wedbook Matrimony) | Complete — `docs/SPEC.md` §9.11 – §9.18 (your ID, link an agent by code, four-step form, privacy settings): OTP login, guest browsing, get-started checklist (agent → profile → ₹150 mock payment → approval), one profile per customer (a paid one is deleted with the agent's approval), photo editor + camera, browse + filters (guests too), interests on behalf of a profile, change agent (`customer_app/`) |
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

Send `app/build/app/outputs/flutter-apk/app-release.apk` (Wedbook Agent, ~40 MB) to agents and
`customer_app/build/app/outputs/flutter-apk/app-release.apk` (Wedbook Matrimony) to customers over
WhatsApp. Release copies sit at the project root as `wedbook-agent-v3.0.0.apk` and
`wedbook-matrimony-v3.0.0.apk`.

**6. Customer app on the emulator:** `cd customer_app && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000`

## Logins

| Who | Phone | Password |
|---|---|---|
| Admin | `9999999999` | `ChangeMe@123` — **change it on first login** |
| Demo agents (after `npm run seed:demo`) | `9000000001` … `9000000003` | `demo1234` |
| Any OTP while `OTP_PROVIDER=mock` (default) | — | code `123456` (with `OTP_PROVIDER=startmessaging` a real SMS arrives — deploy/ORACLE_SETUP.md "StartMessaging") |
| Registration fee while `PAYMENT_PROVIDER=mock` (default) | — | *Pay ₹150* succeeds, *Simulate failure* fails — nothing is charged (with Razorpay test keys: UPI `success@razorpay`) |

Replace the placeholder communities (Community A/B/C) with your real ones from
**More → Admin → Master lists**.

## What's here

- `CLAUDE.md` — rules and working instructions
- `docs/SPEC.md` — full specification: schema, permissions, API, screens
- `backend/` — Express API, Docker Compose, SQL schema + seed data, smoke test
- `app/` — Flutter app for agents (auth, list/filters, detail, add/edit, requests, clients, sharing, shortlists, admin)
- `customer_app/` — Flutter app for customers (Wedbook Matrimony; formerly MILI / Gandharva)
- `deploy/ORACLE_SETUP.md` — copy-paste Oracle VM setup with HTTPS and backups

## Key business rules

- Agents see only profiles shown to their selected communities (a profile's own community, plus any its family added); new agents need admin activation.
- Anyone can share/download profiles, but shares are always masked (no contacts, no uploader identity) and logged.
- The "on request" details (contacts, parents, native and birth place, work place, siblings, family, property) unlock only via uploader/admin approval — a contact request for agents, an accepted *interest* for customers — valid 15 days, revocable.
- A family can switch off any detail except the main photo, age and gender; a switched-off detail behaves like an on-request one everywhere.
- Agent codes and profile IDs are permanent and never reused; a profile ID is visible only to its own agent, admins and the owning customer.
- A customer belongs to one agent, needs that agent's approval, and can change agent only with the current agent's approval.

`backend/test/smoke.mjs` asserts each of these against a running API.
