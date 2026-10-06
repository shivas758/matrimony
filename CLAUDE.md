# Matrimony Agents App — Project Instructions

You (Claude) are building **Mediator**, a matrimony profile-sharing platform for marriage bureau agents.
Read `docs/SPEC.md` fully before writing any code. It is the source of truth.

## Stack (fixed — do not change)
- **Mobile apps:** Flutter (Android-first). The agents' app **Mediator** lives in `app/`; the customers' app **Gandharva** lives in `customer_app/` (org `com.matrimonyagents`, package `com.matrimonyagents.gandharva`). Both talk to the same backend.
- **Backend:** Node.js 20 + Express + PostgreSQL 16. Lives in `backend/`. Runs via Docker Compose.
- **Database schema:** `backend/db/schema.sql` (already written, with seed data). Extend it there; use numbered migration files `backend/db/migrations/00X_*.sql` for later changes.
- **Auth:** JWT (access token, 30-day expiry is fine for v1). Passwords hashed with bcrypt.
- **Photos:** stored on server disk under `backend/uploads/`, served via authenticated routes; public share pages get watermarked copies only.
- **Deployment target:** Oracle Cloud Always Free ARM VM (Ubuntu 24.04, arm64). All Docker images must support linux/arm64. Deployment steps in `deploy/ORACLE_SETUP.md`.

## Core business rules (never violate)
1. Agents only see profiles whose community is in the agent's selected communities. Admins see all.
2. New agents are `pending` until an admin activates them. Pending agents can log in but only see a waiting screen. Forgotten passwords are reset only by an admin (temporary password → forced change on next login); the app never emails anything. Signups (agents and customers) verify the phone with an OTP — mock provider by default (`OTP_PROVIDER=mock`, code `123456`), a real SMS provider by env later. Customers (Gandharva) have no password: every login is phone + OTP. A new customer starts as a `guest` (no agent; browses only photo + age, job, caste, package cards), becomes `pending` when they link an agent, and `active` when that agent approves. Opening profiles and interests needs an active account AND at least one profile paid for (₹150 registration fee per profile, `PAYMENT_PROVIDER=mock` by default, Razorpay by env later). A customer profile is visible to others only when it is paid (in the app, or recorded as cash by the agent) AND its customer is active (SPEC §9.12–9.13). A paid profile is deleted only with the agent's (or an admin's) approval.
3. Any active agent can share/download any visible profile — but shared content and downloads must NEVER include the "on request" fields (SPEC §9.8: contact phone numbers, parents' names/occupations/phones, contact person, native place `city`/`state`, birth place, exact work place / NRI place, siblings, family details, property) or uploader identity. Work country / NRI country are the public location.
4. The same "on request" fields are hidden in-app too. For agents, access requires a contact request approved by the profile's uploader or an admin; for customers, access to another profile requires their *interest* to be accepted by that profile's uploader or an admin. Approval expires 15 days after approval. Admin (or the approver) can revoke early.
5. Every share and every contact approval is logged (share_logs, contact_requests).
6. Public share links (`/p/:token`) show a masked profile page: photos (watermarked), bio, community, education, horoscope — no contacts, no uploader info. Links can be deactivated.
7. A customer belongs to at most one agent (exactly one once linked) and may own up to 5 profiles; every profile's `uploaded_by` is always that agent. Changing agent needs the current agent's (or an admin's) approval and moves the profiles with the customer (a guest / pending / rejected customer may simply link another agent). Customers never see who uploaded a profile; the two agents involved in an interest see each other's name, agency and phone so they can talk.

## Working style
- Build backend first, test with curl, then build the Flutter app against it.
- Keep the API base URL in one Flutter config file (`app/lib/config.dart`) so it can point to localhost during dev and the Oracle VM in production.
- Write seed/master data only via schema.sql or migrations — never hardcode master lists in app code; the app must fetch them from the API.
- When the user asks for a new feature, update `docs/SPEC.md` first, then implement.
- Target: a working APK the user can send to agents over WhatsApp (no Play Store needed for v1).

## Directory map
- `docs/SPEC.md` — full specification (schema, screens, API, permissions)
- `backend/` — Express API + Docker Compose + SQL
- `app/` — Flutter app for agents (Mediator)
- `customer_app/` — Flutter app for customers (Gandharva)
- `deploy/ORACLE_SETUP.md` — copy-paste server setup for the Oracle VM
