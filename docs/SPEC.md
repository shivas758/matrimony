# Mediator (Matrimony Agents) App — Full Specification

The product is branded **Mediator — Matrimony Partners** (the app name, launcher icon, share pages, PDFs and cards). The Android package id stays `com.matrimonyagents.matrimony_agents` so existing installs update in place. Since v2.1 a second app, **Gandharva**, lets the agents' customers browse and mark interest — see §9.

A private platform for marriage bureau agents to organise, filter, and share bride/groom profiles, replacing unstructured WhatsApp forwarding. Agents: 10–50. Profiles: up to ~5,000 with photos.

## 1. Users & roles

| Role  | Abilities |
|-------|-----------|
| Agent | Sign up, select communities, browse/filter profiles in their communities, upload profiles, share/download (masked), request contact details, approve contact requests for their own uploads, shortlist profiles for clients |
| Admin | Everything an agent can do across ALL communities + activate/suspend agents, manage master tables, approve/revoke any contact request, deactivate profiles and share links, view logs, manage customers |
| Customer (Gandharva app, §9) | Attached to one agent; signs up with phone + OTP, waits for the agent's approval, fills their own profile, browses profiles in their agent's communities, marks *interested*, sees a profile's on-request fields once the other side's agent accepts, asks to change agent |

Agent lifecycle: `pending` → (admin activates) → `active` → (admin may) `suspended`.
Pending agents see only a "Your account is awaiting approval" screen after login.

## 2. Database schema

Authoritative DDL in `backend/db/schema.sql`. Summary:

**Master tables** (all: id, name, active boolean, sort_order): `communities`, `professions`, `educations`, `marital_statuses`, `complexions` (Very Fair, Fair, Wheatish, Wheatish Brown, Dark), `countries` (NRI countries — US, UK, Australia, Canada, Germany, France, Russia, Gulf states, Singapore … plus "Other"), `religions` (Hindu, Muslim, Christian, Sikh, Jain, Buddhist, Parsi, Jewish, Other), `languages` (Telugu, Hindi, English, Tamil, Kannada, Malayalam, Marathi, Gujarati, Bengali, Punjabi, Urdu, Odia, Konkani, Tulu, … Other — one list serves both mother tongue and known languages), `food_habits` (Vegetarian, Non-Vegetarian, Eggetarian, Fish only (Pescatarian), Occasionally Non-Veg, Jain, Vegan), `occupation_types` (Private job, Government job, Business, Self-employed, Professional, Farmer / Agriculture, Student, Not working, Other). `countries` starts with **India** (sort 0) because nationality, birth country, work country and education countries pick from it too. Special:
- `zodiac_signs`: id, english_name (Aries…), indian_name (Mesha…) — paired.
- `nakshatrams`: id, name — all 27 seeded.
- `subcastes`: id, community_id → communities, name, active, sort_order. UNIQUE (community_id, name). A subcaste belongs to exactly one community (the "main caste"). Unlike the other masters, **any active agent can add one just by typing it** on the profile form: the API finds-or-creates it (trimmed, case-insensitive) under the profile's community. Admins can rename/deactivate via the master editor. Not seeded.
Admins can add/edit/deactivate master rows from the admin screens. Seed data is a starting point; the user will expand lists over time.

**agents**: id, full_name, phone (unique, login id), password_hash, agency_name, role ('agent'|'admin'), status ('pending'|'active'|'suspended'), must_change_password (set when an admin issues a temporary password; cleared by `/auth/change-password`), **city** (shown in the customer-facing agent directory), **registration_token** (the agent's public form link `/r/:token`, §9.3), created_at.
**agent_communities**: agent_id, community_id (M:N; chosen at signup, editable later — additions after signup require admin approval via `community_change_requests`).
**password_reset_requests**: id, agent_id, status ('pending'|'approved'|'rejected'), requested_at, decided_by, decided_at. Created by "Forgot password?" on the login screen; settled by an admin who sets a temporary password.

**profiles**: id, uploaded_by → agents, **customer_id** → customers (nullable, unique; the Gandharva account that owns it, §9.2), full_name, gender ('bride'|'groom'), dob, height_cm, weight_kg, complexion_id → complexions, marital_status_id, community_id, subcaste_id → subcastes (nullable; must belong to the same community_id — enforced by the API), gothram (free text), nationality_id → countries, education_id, education_details (free text: "other education details"), profession_id, profession_details (free text: employer, designation), occupation_type_id → occupation_types, work_country_id → countries (public coarse location), income_text, other_income, is_nri boolean, nri_country_id → countries, zodiac_id, nakshatram_id, birth_time (TIME; "HH:MM" 24-hour on the wire; public like star/rasi), religion_id → religions, mother_tongue_id → languages, food_habit_id → food_habits, about, status ('active'|'engaged'|'married'|'hidden'|'on_hold'), created_at, updated_at — and the **PROTECTED ("on request") fields**: **work_place, nri_place** (exact place; only meaningful when is_nri — the API nulls nri_* otherwise), **birth_place, birth_state, birth_country_id**, **has_siblings** (BOOLEAN, NULL = not recorded, FALSE = none, TRUE = see counts), **siblings_count** (0–20), **siblings_details**, **elder_sisters, younger_sisters, elder_brothers, younger_brothers** (0–20), **family_details, property_share, property_details, city, state** (= native place), **father_name, father_occupation, father_phone, mother_name, mother_occupation, mother_phone, contact_name, contact_phone**.
> `on_hold` = talks in progress: hidden from other agents like engaged/married, except the agent whose hold request was approved (see `hold_requests`).
> The bold fields are the PROTECTED fields (rules 3/4 in CLAUDE.md, §9.8): everything on the hand-written "On request" sheet. Before v2.1 `work_place`, `birth_place`, the siblings count and `family_details` were public; since 005 they are on request too. `work_country` / NRI country are the public location.

**profile_education_levels**: profile_id, level ('below_10th'|'10th'|'intermediate'|'graduation'|'post_graduation'), details, country_id → countries. PRIMARY KEY (profile_id, level). On the wire `education_levels[{level, details, country}]` (§9.7).

**customers**, **otp_codes**, **customer_interests**, **agent_change_requests**: see §9.

**profile_languages**: profile_id, language_id (M:N — the languages the person knows; the mother tongue is the single column above). Sent/received as `known_language_ids[]` / `known_languages[{id,name}]`.

**profile_photos**: id, profile_id, file_path, is_primary, sort_order.

**contact_requests**: id, profile_id, requester_id, status ('pending'|'approved'|'rejected'|'revoked'|'expired'), requested_at, decided_by, decided_at, expires_at (decided_at + 15 days on approval), note.
A requester has active access iff a row exists with status='approved' AND expires_at > now(). Expiry check happens at read time (plus a daily job may flip status to 'expired' for tidiness).

**hold_requests**: id, profile_id, requester_id, status ('pending'|'approved'|'rejected'|'cancelled'|'released'), note, requested_at, decided_by, decided_at, released_by, released_at.
The HOLD workflow: **any** active agent who can see a profile may ask to put it on hold (their client is in talks with the family). The **uploader or an admin** approves or rejects. An approved hold flips the profile to `status = 'on_hold'`, which hides it from every other agent (and 404s its public links) until the **holder, the uploader or an admin** releases it. A hold placed by the uploader/admin themselves is approved on the spot; approving one request auto-rejects the other pending ones on that profile (one holder at a time). Editing the status directly (PATCH) keeps the log honest: → `on_hold` inserts an approved row by the editor, leaving `on_hold` releases the approved row. Rows are never deleted — the table is the hold log.

**share_tokens**: id, profile_id, token (random 22-char url-safe, unique), created_by, active boolean, created_at. Public masked page served at `/p/:token`.

**share_logs**: id, profile_id, agent_id, shared_at, method ('whatsapp'|'download'|'link'|'pdf').

**shortlists**: id, agent_id, profile_id, client_label (free text, e.g. "Ramesh's daughter"), created_at. Unique (agent_id, profile_id, client_label).

**community_change_requests**: id, agent_id, community_id, status ('pending'|'approved'|'rejected'), decided_by, decided_at.

## 3. Visibility & permission rules

1. Profile list/detail queries for an agent: `WHERE profiles.community_id IN (agent's communities) AND profiles.status = 'active'`. Agents also always see their OWN uploads regardless of status, and a profile that is `on_hold` **for them** (their approved `hold_requests` row) stays visible to them. Admins see everything with a status filter.
2. Profile detail API returns the protected fields (`PROTECTED_FIELDS` in `backend/src/lib/profiles.js`: native place `city`/`state`, birth place/state/country, work place, NRI place, parents' names/occupations/phones, contact person, every siblings field, family details, property share/details — the full list is in §9.8) ONLY if: requester is the uploader, or an admin, or has an unexpired approved contact_request (agents); or, for customers, it is their own profile or their interest in it is accepted and unexpired (§9.4). Otherwise those fields are omitted (not blanked — omitted) and the response includes `contact_access: 'none'|'pending'|'granted'` + `contact_expires_at`. List rows never carry them.
3. Share text, share pages, and PDF/image downloads never contain protected fields or uploader identity — even for users who have contact access. They show `work_country` / NRI country as the location; the exact work place, birth place, siblings, family details and property are on request (§9.8). Everything that leaves the app comes from one list, `publicRows()` in `backend/src/lib/card.js`, so the card, the PDF and the public page can never disagree on what is exposed.
   The list filter `city` ("Place") matches `work_place`, `nri_place` **and** the native `city`, so profiles added before `work_place` existed stay findable; matching never reveals the native place itself.
4. All timestamps stored UTC; app displays IST.

## 4. API (Express, prefix /api)

All error responses are `{error: '<stable_code>', message: '<human text>', details?: [...]}`.
Everything under `/api` except `/auth/*`, `/masters` and `/health` needs a bearer token from
an **active** agent; pending/suspended agents get `403 account_pending` / `403 account_suspended`.

Auth
- POST /auth/otp/send {phone} → mock/real OTP for agent signup (§9.1); POST /auth/otp/verify {phone, code} → {verification_token}
- POST /auth/signup {full_name, phone, password, agency_name, community_ids[], phone_verification_token} → creates pending agent (`400 phone_not_verified` without a valid token for that number)
- POST /auth/login {phone, password} → {token, agent} (pending agents get token but role-gated). `agent.must_change_password: true` means the agent logged in with a temporary password: every data route answers `403 password_change_required` until `/auth/change-password` succeeds. Only `/auth/me` and `/auth/change-password` work in that state.
- GET /auth/me — allowed while pending/suspended so the app can show the right screen
- POST /auth/change-password {current_password, new_password} — also clears `must_change_password`. Re-using the temporary password is refused (`400 same_password`).
- POST /auth/forgot-password {phone} — **always 200** (no number enumeration). If the phone belongs to an agent and no request is pending, creates a `password_reset_requests` row that admins see in notifications and under Admin → Password resets. Rate-limited like login. The admin verifies the caller out of band (they see name + phone), sets a temporary password, and tells the agent by phone/WhatsApp.

Masters
- GET /masters → all master tables in one payload (communities, subcastes, professions, educations, marital_statuses, complexions, countries, religions, languages, food_habits, occupation_types, zodiac_signs, nakshatrams). Each subcaste row carries its `community_id` so the app can scope it to the selected community. No auth — the signup screen needs it. Inactive rows are omitted unless an admin passes `?include_inactive=true`.
- Admin CRUD: POST /admin/masters/:table, PATCH /admin/masters/:table/:id. For `subcastes`, POST requires `community_id`.

Profiles
- GET /profiles — filters: gender, age_min, age_max (from dob), height_min, height_max (cm; the app shows a feet/inches slider), community_id[], subcaste_id[], education_id[], profession_id[], marital_status_id[], complexion_id[], religion_id[], mother_tongue_id[], language_id[] (known languages, any of), food_habit_id[], zodiac_id, nakshatram_id, nri (true|false), country_id[] (NRI country, any of), city ("Place": matches work_place / nri_place / native city), q (name search), status (active|engaged|married|hidden|on_hold), mine=true, sort (newest|oldest|name|age_asc|age_desc), page, limit → {total, page, limit, profiles[]}
- POST /profiles (multipart with photos, max 8, 10 MB each). Subcaste is accepted as `subcaste_id` **or** free-text `subcaste_name`: a name is trimmed, matched case-insensitively within the profile's community, and **created if missing** — that is how agents grow the list. A `subcaste_id` belonging to a different community is rejected with `400 subcaste_mismatch`. Same on PATCH. `is_nri` accepts true/false (multipart strings are fine); when false, `nri_country_id`/`nri_place` are stored as null. `birth_time` is "HH:MM" (24-hour; `400` otherwise; an empty string clears it) and `birth_place` free text — both public horoscope fields, returned on list rows too. `known_language_ids` is a JSON array, a comma-separated string or a repeated multipart field (`[]` clears; unknown ids → `400 invalid_reference`). `has_siblings` is tri-state (true/false/null); when it is false the API stores `siblings_count = 0` and clears `siblings_details`, when null both are null.
- POST /profiles/parse — **AI import.** Multipart: one `file` (PDF, JPG/PNG photo of a bio-data, or `.txt`) *or* a `text` field with pasted bio-data. Returns `{draft, unmatched, warnings, ai: {model, input_tokens, output_tokens}}`. `draft` is a profile body ready to pre-fill the form: master fields are resolved to ids when the extracted name matches a master row (case-insensitive, light normalisation such as "B.Tech" ≈ "B.Tech / B.E."); anything that did not match is returned as raw text under `unmatched` (e.g. `unmatched.education: "B.Tech (CSE)"`) for the agent to pick manually. **Nothing is saved** — the agent reviews and submits the normal POST /profiles. Contact name/phone land in the draft's protected fields exactly as with manual entry. Errors: `503 ai_not_configured` when `ANTHROPIC_API_KEY` is unset (the app hides the button), `413` over 10 MB, `422 unreadable_document` when nothing usable was found, `429` past 30 parses/hour/agent.
- GET /profiles/:id — respects contact rule; adds `contact_access`, `contact_expires_at`, `contact_request_status` (raw latest status, so the app can distinguish "rejected" from "never asked"), `can_edit`, `can_delete`, `is_mine`, plus the hold state: `hold_request_status` / `hold_request_id` (the caller's latest hold request) and — uploader/admin only — `held_by` {id, full_name, agency_name, hold_request_id, since} and `pending_hold_requests`.
- PATCH /profiles/:id — uploader or admin only (incl. status changes; `status: 'on_hold'` / leaving it keeps `hold_requests` in step, see §2)
- DELETE /profiles/:id — **uploader or admin**. Hard delete: photo files, contact/hold requests, share tokens/logs and shortlist rows go with it. Others get `403 not_your_profile`.
- POST /profiles/:id/photos, DELETE /photos/:photoId, POST /photos/:photoId/primary
- GET /photos/:id — authenticated, un-watermarked; only for profiles the caller can see

Contact requests
- POST /profiles/:id/contact-request
- GET /contact-requests?box=inbox|sent[&status=…] — inbox = requests on my uploads (admin: all). Inbox rows include `requester`; sent rows never do (uploader identity stays hidden).
- POST /contact-requests/:id/approve | /reject | /revoke (revoke: admin or original approver). Approved rows carry `days_left`, computed by the database so the countdown uses one clock.

Hold requests (§2 hold_requests)
- POST /profiles/:id/hold-request {note} — any active agent who can see the profile. `201` with the row; for the uploader/admin the row is already `approved` and the profile is `on_hold`. `409 not_active` unless the profile is active, `409 already_on_hold`, `409 already_pending`.
- GET /hold-requests?box=inbox|sent[&status=…] — inbox = holds asked on my uploads (admin: all), rows include `requester`; sent = my own asks, never the uploader. Every row carries `is_mine` and the profile's current `profile_status`.
- POST /hold-requests/:id/approve | /reject — uploader or admin. Approve sets the profile `on_hold` and auto-rejects the other pending requests on it.
- POST /hold-requests/:id/release — the holder, the uploader or an admin; profile back to `active`.
- POST /hold-requests/:id/cancel — the requester withdraws a pending ask.

Sharing
- POST /profiles/:id/share {method} → logs share; for method 'whatsapp'/'link' returns {share_url, share_token_id, summary, whatsapp_text} (creates or reuses active share_token); for 'download' returns a masked, watermarked profile card JPEG; for **'pdf'** returns a masked A4 bio-data PDF (`application/pdf`, attachment) — brand header, watermarked photos (primary + up to 3 thumbnails), the public rows grouped Personal / Education & Career / Horoscope, About, agency footer. Rendered with `pdfkit` and the bundled Poppins / Playfair Display fonts (`backend/src/assets/fonts`).
- GET /profiles/:id/share-tokens — uploader or admin
- Public (no auth): GET /p/:token → HTML masked profile page (server-rendered by Express; mobile-friendly; Mediator navy/gold styling; `X-Robots-Tag: noindex`; Open Graph title/description/image so WhatsApp shows a preview card; "Contact your agent for details" footer). GET /p/:token/photo/:photoId serves the watermarked copy. Non-active profiles (hidden, engaged, married) and deactivated tokens 404.
- POST /share-tokens/:id/deactivate — uploader or admin

Shortlist
- POST /profiles/:id/shortlist {client_label}, GET /shortlists (grouped by client_label), GET /shortlists/labels, DELETE /shortlists/:id

Agent self-service
- GET /my/communities → my communities + my community-change requests
- POST /my/community-requests {community_id} → pending request for admin approval
- PATCH /my/account {city?, agency_name?} → my directory details (§9.5)

Customers, interests, agent changes, registration link (§9): `/clients*`, `/interests*`, `/agent-change-requests*`, `/customer/*`, public `/r/:token`.

Admin
- GET /admin/agents?status=pending|active|suspended&q=
- POST /admin/agents/:id/activate | /suspend | /role {role}
- PUT /admin/agents/:id/communities {community_ids[]}
- GET /admin/community-requests, POST /admin/community-requests/:id/approve|reject
- GET /admin/password-resets?status=pending|approved|rejected — rows carry agent name, phone, agency
- POST /admin/password-resets/:id/approve {temporary_password} — sets the agent's password to the temporary one, flags `must_change_password`, marks the request approved. POST /admin/password-resets/:id/reject.
- POST /admin/agents/:id/reset-password {temporary_password} — same effect without a request (agent phoned instead). Admins cannot reset their own this way (`400 cannot_change_self`).
- GET /admin/logs/shares, GET /admin/logs/contacts (both filterable by agent_id/profile_id, paginated)
- GET /admin/stats — counts for the admin dashboard (incl. `pending_password_resets`, `pending_hold_requests`, `on_hold_profiles`)
- DELETE /admin/profiles/:id — hard delete of any profile incl. photo files; same code path as the uploader's DELETE /profiles/:id

Notifications (v1 = in-app polling)
- GET /notifications → pending contact requests on my uploads, decisions on my sent requests, pending hold requests on my uploads (`hold_request_received`) and decisions/releases on my hold asks (`hold_request_decided`), community request decisions, and (admins) agents awaiting approval + password reset requests. Returns {badge, counts, items[]}; `counts.contact_requests_inbox + counts.hold_requests_inbox` drives the Requests tab badge, `counts.pending_password_resets` the admin badge. (Push notifications via FCM = v2.)

## 5. Flutter app screens

1. **Splash / auto-login**
2. **Login** (phone + password, **Forgot password?** → enter phone → "the admin will contact you with a temporary password") · **Signup** (details + multi-select community chips) · **Pending approval screen** · **Set new password screen** — shown instead of Home whenever `must_change_password` is true (temporary password + new password + confirm; logout is the only other action).
3. **Home: Profile list** — card grid (photo, name, age with the DOB in brackets — "27 yrs (12 Apr 1998)", height as 5' 3", community, work place / NRI country, NRI badge, "On hold" chip when the profile is held for me); filter bar → **Filter sheet**: gender toggle, AGE RANGE SLIDER, HEIGHT RANGE SLIDER (labels in feet/inches, sent as cm), multi-select chips for community/subcaste (subcaste chips show only for the selected communities)/education/profession/marital status/complexion/religion/mother tongue/languages known/food habit, NRI switch + multi-select country picker (shown when NRI is on), zodiac & nakshatram dropdowns, place text. Saveable filter presets (local).
4. **Profile detail** — collapsing photo header with the name, a chip row (gender, age + DOB, community, NRI, status), an at-a-glance tile grid, then cards: Details (age, DOB, height as feet/inches + cm, weight, complexion, marital status, religion, community, subcaste, gothram, mother tongue, languages known, food habit, education + details, profession + details, work place, NRI country/place, income), Horoscope (star, rasi, date of birth, birth time in 12-hour form, birth place), Family (siblings count + siblings details, family details), About; contact section shows Request Contact / Pending / **personal details** (native place, father & mother name/phone, contact person) + days-left countdown per access state. Buttons: **Share** opens a sheet with three ways to send — *WhatsApp message + link* (share_url + summary text via `url_launcher` → `https://wa.me/?text=...`), *PDF bio-data* (POST share {method:'pdf'} → temp file → system share sheet, so the agent picks WhatsApp and it arrives as a document), *Photo card* (masked JPEG) — and Shortlist. App-bar menu: **Request hold** (any agent) / **Put on hold** (uploader, admin), **Cancel hold request**, **Release hold** (holder, uploader, admin), **Delete profile** (uploader, admin — confirmation dialog). A hold banner above the buttons shows the current state: my pending ask, "on hold for your client", or (uploader/admin) who holds it and how many asks are waiting.
5. **Add/Edit profile** — form with dropdowns from /masters, DOB picker, height picker (feet/inches shown first), weight, complexion, marital status, **religion**, **mother tongue**, **languages known** (multi-select chips), **food habit**, gothram, education + description, profession + description, work place, NRI checkbox that reveals country dropdown + place, a **Siblings** block (Not recorded / No / Yes; Yes reveals the count and a description that stays in-app), a Horoscope block with nakshatram, rasi, **birth time** (time picker, sent as "HH:MM") and **birth place** (free text), multi-photo upload, and a **Personal details** block (native place city/state, father & mother name/phone, contact person name/phone) marked "visible only after approval". **Subcaste** is an autocomplete scoped to the chosen community: pick an existing one or type a new one, which is created on save. A **Fill from bio-data** button at the top takes a PDF, a photo, or pasted text, calls POST /profiles/parse, and pre-fills every field it could match; values that did not match a master row appear as hints beside the field. The agent reviews everything and saves as usual — the AI never writes to the database.
6. **My uploads** — list with status chips (age + DOB on each row); change status (active/on hold/engaged/married/hidden). Delete lives on the detail screen's menu.
7. **Requests** — tabs: Inbox (approve/reject) and Sent (status + expiry). Each tab lists **hold requests** first (inbox: Put on hold / Reject, Release hold; sent: Cancel, Release when it is mine) and contact requests below; the tab badge counts both.
8. **Shortlists** — grouped by client label.
9. **Admin section** (admins only): pending agents, agent list (with **Reset password** per agent), **password reset requests** (approve = type a temporary password; reject), master table editor (incl. complexions, countries, religions, languages and food habits), community change requests, logs.
10. **Settings** — my communities (+ request to add), change password, logout.

Navigation: bottom bar with **Profiles · Requests · Clients · Shortlists · More**; My uploads is reachable
from the Profiles app bar and from More; Admin and Settings live under More. Clients is §9.11.

UI: Material 3, clean and legible for non-technical users, large touch targets, English labels
(all strings live in `app/lib/ui/strings.dart` for future Telugu/Hindi localization).

Branding: **Mediator — Matrimony Partners.** Palette navy `#0F2F52` / deep navy `#081C33` / gold
`#C9962E` on ivory `#F7F5F0` (`AppColors` in `app/lib/ui/theme.dart`, mirrored in the backend card,
PDF and public page). Type: Poppins for text, Playfair Display for the wordmark and headlines
(bundled in `app/assets/fonts` and `backend/src/assets/fonts`). The logo is the gold
heart-couple-handshake icon from the supplied artwork (`app/assets/logo/mediator_source.jpg`);
`cd app && node tool/gen_logo.mjs` keys the icon out of its background, upscales it and composites
it onto a vector navy tile, producing the in-app assets (`AppLogo` tile, `AppLogoMark` icon-only,
`AppWordmark`), the Android launcher icon (legacy PNGs plus an adaptive icon with background,
foreground and monochrome layers) and the native splash image. Re-run the script rather than
touching the PNGs by hand; the wordmark text in the artwork is deliberately not used.

`API_BASE_URL` is a `--dart-define` read only by `app/lib/config.dart`. Plain HTTP is blocked
except for `10.0.2.2`/`localhost` via `android/app/src/main/res/xml/network_security_config.xml`.

## 6. Non-functional

- Docker Compose: `api` (node:20-alpine) + `db` (postgres:16-alpine) + volume for uploads and pgdata. All arm64-compatible — `sharp` and `bcrypt` both ship prebuilt `linux-arm64-musl` binaries, so nothing compiles on the VM.
- The API publishes on `127.0.0.1:3000` only; Caddy on 443 is the sole public entry point.
- The image installs `font-dejavu` — `sharp` renders watermark and share-card text from SVG and needs real fonts present. The PDF (`pdfkit`, pure JS, arm64-safe) embeds the bundled Poppins / Playfair Display TTFs instead, so it looks the same everywhere.
- Images resized server-side (max 1280px, ~80% JPEG) via `sharp`; watermark applied on shared/downloaded copies only.
- Rate-limit the credential endpoints (`/auth/login`, `/auth/signup`, `/auth/change-password`) at 50 per 15 min per IP. `/auth/me` is deliberately excluded — the app calls it on every launch and while the pending screen polls. Validate all input with zod.
- Nightly `deploy/backup.sh` via cron: `pg_dump` + uploads tarball into `~/backups`, 14-day retention, failures logged rather than silent. Deploy doc includes rclone → Oracle Object Storage as the off-box copy.
- Env config via `.env` (see `backend/.env.example`). JWT secret must be generated, never committed. `deploy/package.sh` builds the server tarball and excludes every `.env`.
- **AI import** (`POST /profiles/parse`) calls the Anthropic API through `@anthropic-ai/sdk` with structured output (`client.messages.parse` + a zod schema), model from `CLAUDE_MODEL` (default `claude-opus-5`), `output_config.effort: medium`. Requires `ANTHROPIC_API_KEY` in `.env`; when unset the endpoint returns 503 and the app hides the button, so the rest of the system is unaffected. The uploaded document is sent to Anthropic for extraction and is not stored on the server. Bio-data contains personal data — agents should be told this before using it. Cost is roughly ₹1–3 per parse at Opus pricing; set `CLAUDE_MODEL=claude-haiku-4-5` for ~5× cheaper, slightly less accurate extraction.

## 7. Build order

1. ✅ Backend: schema up, auth, masters, profiles CRUD + filtering, contact requests, share endpoints, public masked page.
2. ✅ Flutter: auth flow → list/filter → detail → add profile → requests → sharing → shortlists → admin.
3. `flutter build apk --release` → distribute APK directly.
4. Deploy backend to Oracle VM per `deploy/ORACLE_SETUP.md`.

Testing: `cd backend && npm run smoke` runs 1014 end-to-end assertions (38 steps) against a live
API, covering every rule in §3, §9 and CLAUDE.md (steps 24–27 cover birth details, the hold
workflow, delete, and religion / languages / food habit / siblings + the PDF share; steps 28–36
cover OTP hardening, customer signup and pending gating, the Clients routes, the customer browse
scope, interests end to end, agent change, the public registration form, the §9.7 fields and admin
customers; step 37 pins the review fixes — shortlist rows carry no protected field, suspended customers cannot edit their profile, revoking an interest also revokes the auto-granted contact access, bad query/file input answers 400). Each step rotates an `X-Forwarded-For` so the auth rate limiter does not trip.
`npm run seed:demo` fills the database with 2 communities, 3 agents, 12 profiles and 6 Gandharva
customers (OTP `123456`) for app development. `cd app && flutter test` and
`cd customer_app && flutter test` cover the models and filter serialisation.

## 9. Customers, the Gandharva app, OTP signups (v2.1; guest mode, fee and 5 profiles: §9.12, v2.2; guest filters, delete requests, cash: §9.13, v2.3)

Two apps now share one backend:

| App | Users | Package | Directory |
|---|---|---|---|
| **Mediator** (existing) | agents + admins | `com.matrimonyagents.matrimony_agents` | `app/` |
| **Gandharva** (new) — "Connecting Hearts, Creating Families" | customers (the brides/grooms or their families) | `com.matrimonyagents.gandharva` | `customer_app/` |

A **customer** is always attached to exactly one **agent**. Customers never talk to each other or to
other agents directly: they browse, mark *interested*, and their agent (or the other party's agent)
does the rest by phone. The Gandharva logo is `new content/Gandharva.jpeg` (maroon disc, rose-gold
couple + lotus heart); `customer_app/tool/gen_logo.mjs` cuts the disc out of its black background
and produces the in-app assets, launcher icons and splash. Palette: maroon `#4A1A29` / deep maroon
`#2E0F18` / rose gold `#D4A28C` / rose light `#F0D6CC` on blush `#FAF3F0` (`AppColors` in
`customer_app/lib/ui/theme.dart`, mirrored in the public registration form). Type: Poppins +
Playfair Display, same files as Mediator.

### 9.1 OTP (mock now, real SMS later)

Both apps verify the mobile number with a one-time code **at signup**. Agents keep their password
login; customers have no password — every login is phone + OTP.

- `otp_codes` rows: `phone`, `purpose` (`agent_signup` | `customer_login`), `code_hash`
  (sha256 of `JWT_SECRET + phone + purpose + code`), `expires_at` (5 min), `attempts` (max 5),
  `consumed_at`. Max 5 sends per phone per hour, 30 s between sends (`429 otp_cooldown` /
  `429 otp_limit`).
- Provider is chosen by env: `OTP_PROVIDER=mock` (default) or `msg91`.
  **mock** never sends anything: the code is always `OTP_MOCK_CODE` (default `123456`) and, when
  `OTP_MOCK_ECHO=true` (default when the provider is mock), the send response carries
  `mock_code` so the apps can show "Test mode — enter 123456". **msg91** posts to MSG91's OTP API
  (`MSG91_AUTH_KEY`, `MSG91_TEMPLATE_ID`, `MSG91_SENDER`) with our own generated code; the verify
  logic is identical for both providers. Switching to production = setting those four env vars
  and restarting — nothing else changes.
- Send response: `{sent: true, mock: bool, expires_in: 300, retry_after: 30, mock_code?}`.
- Verify returns a short-lived **phone verification token** (JWT, 15 min, claims
  `{typ:'phone_verification', phone, purpose}`) that the signup call must present. A code can be
  verified once (`400 invalid_otp`, `410 otp_expired`, `429 too_many_attempts`).

Agent signup (Mediator): `POST /auth/otp/send {phone}` (purpose agent_signup; `409 phone_taken`
if the number is already an agent) → `POST /auth/otp/verify {phone, code}` →
`{verification_token}` → `POST /auth/signup {…as before, phone_verification_token}`
(`400 phone_not_verified` when the token is missing, expired, or for another number).
Login and forgot-password are unchanged.

### 9.2 Customers (`customers` table)

`id, full_name, phone (unique, login id), agent_id → agents, status ('pending'|'active'|'rejected'|'suspended'), source ('app'|'form'), phone_verified_at, approved_by, approved_at, last_login_at, created_at, updated_at`.

Lifecycle: `pending` → (agent or admin approves) `active`; agent/admin may `reject` (pending) or
`suspend` / re-`activate` (active). Pending customers can log in, see the waiting screen, and
**fill in their profile** while they wait; everything else answers `403 account_pending`.

One profile per customer: `profiles.customer_id` (unique, `ON DELETE SET NULL`). The profile's
`uploaded_by` is always the customer's **current agent** — so the agent sees it under My uploads,
approves contact requests on it, and it moves with the customer on an agent change. A profile the
customer creates while still pending is stored `hidden`; approving the customer flips it to
`active`. A profile created after approval is `active` immediately (the agent can hide it from
My uploads as usual).

Customer tokens are JWTs with `{sub: customerId, typ: 'customer'}`; agent routes reject them
(`401 invalid_token`) and customer routes reject agent tokens. `requireCustomer` loads the customer
plus their agent's community ids; `requireActiveCustomer` additionally needs `status = 'active'`.

### 9.3 Two ways to register

**A. In the Gandharva app.** `POST /customer/auth/otp/send {phone}` → `POST /customer/auth/otp/verify {phone, code}`:
- number already a customer → `{token, customer}` (login; sets `phone_verified_at` / `last_login_at`)
- unknown number → `{new: true, verification_token}` → `POST /customer/auth/signup {full_name, agent_phone, phone_verification_token}` → `201 {token, customer}` with `status: 'pending'`. `agent_phone` must belong to an **active** agent (`404 agent_not_found`, `400 agent_not_active`). The customer waits for that agent's approval (Mediator → Clients).

**B. The agent's registration form (paper form → web).** Every agent has a permanent link
`PUBLIC_BASE_URL/r/<agents.registration_token>` (`GET /clients/registration-link` →
`{url, whatsapp_text}`; `POST /clients/registration-link/rotate` invalidates the old one).
The agent sends it on WhatsApp. `GET /r/:token` is a public, server-rendered, mobile-friendly
HTML form (Gandharva styling, agent's name/agency in the header, master lists embedded as
`<select>`s, `noindex`) with the fields of the paper registration form (§9.7) plus **"Your mobile
number"** (required — it becomes the Gandharva login) and up to 4 photos. `POST /r/:token`
(multipart, rate-limited 20/hour/IP) creates the customer (`pending`, `source: 'form'`,
`phone_verified_at: null`) **and** the profile (`hidden`, `uploaded_by` = the agent,
`customer_id` set, photos stored) in one transaction, then renders a thank-you page naming the
agent. `409 phone_taken` renders "This number is already registered — open Gandharva and log in".
Unknown/rotated token or inactive agent → 404 page. No OTP on the web form: the agent vets the
person, and a later Gandharva login still requires the OTP.

### 9.4 Interests (`customer_interests`)

`id, customer_id, profile_id, status ('pending'|'accepted'|'declined'|'withdrawn'|'revoked'), note, created_at, decided_by → agents, decided_at, access_expires_at`. `UNIQUE (customer_id, profile_id)` — re-expressing after `withdrawn`/`revoked`/`declined` reuses the row and sets it back to `pending` (declined ones are allowed again, agents may have talked since).

- Customer marks interest: `POST /customer/profiles/:id/interest {note?}` → `201 {interest}`; `409 already_pending` / `409 already_accepted`; `400 own_profile`.
- Withdraw a pending one: `POST /customer/interests/:id/withdraw`.
- Who decides: the target profile's **uploader** or an **admin**: `POST /interests/:id/accept | /decline`; `POST /interests/:id/revoke` (accepted → revoked, access ends now; uploader/admin).
- **Accept** sets `access_expires_at = now() + CONTACT_ACCESS_DAYS` (15). While it is in the future the customer's `GET /customer/profiles/:id` includes the on-request fields (§3.2) and `interest.days_left`. Accepting also **auto-grants contact access to the customer's agent**: an approved `contact_requests` row (requester = customer's agent, decided_by = the accepting agent, note `via interest #<id>`, same expiry) is inserted unless the agent already has a live one (a pending one is approved instead). Every acceptance is therefore in the contact log (CLAUDE.md rule 5).
- Both agents can reach each other: interest rows returned to agents carry `customer` (name, phone only for the customer's own agent/admin), `customer_profile` (id, name, gender, age, community, photo) and, for the uploader, `customer_agent` {id, full_name, agency_name, phone}; for the customer's own agent they carry `target_agent` {id, full_name, agency_name, phone} (the uploader). This is the one place uploader identity is shown to another agent, and only between the two agents whose clients are involved.
- Visibility side-effect: while an interest is `pending` or `accepted`, the interested customer's own profile becomes visible to the target profile's uploader (extra branch in `visibilityClause`), even outside the uploader's communities — they need to see who is asking. Their contact access to it still follows the normal rules.

Agent listing: `GET /interests?box=received|clients[&status=]` — `received` = interests on my uploads (admin: all), `clients` = interests my clients expressed (admin: all). `GET /clients/:id` also embeds that client's interests.

### 9.5 My clients (Mediator → Clients tab)

- `GET /clients?status=pending|active|rejected|suspended&q=` → `{clients: [{id, full_name, phone, status, source, created_at, approved_at, profile: {id, full_name, gender, age, community, status, photo_url}|null, interests_count, pending_agent_change: {id, to_agent:{…}}|null}]}`. Agents see their own clients; admins see all (rows add `agent: {id, full_name, agency_name}`).
- `GET /clients/:id` → the row above plus `interests[]` (the client's interests with target profile summary, status, `days_left`, `target_agent`) and `agent_change_requests[]`.
- `POST /clients/:id/approve` (pending → active; a `hidden` profile becomes `active`), `/reject` (pending → rejected), `/suspend` (active → suspended), `/activate` (suspended → active). Own clients or admin; `409 wrong_status` otherwise.
- `GET /clients/registration-link`, `POST /clients/registration-link/rotate` (§9.3).
- Admin: `GET /admin/customers?status=&q=`, `POST /admin/customers/:id/activate|suspend|reject`, `PUT /admin/customers/:id/agent {agent_id}` (reassign; moves the profile's `uploaded_by` too). `GET /admin/stats` adds `pending_customers`, `active_customers`, `pending_interests`, `pending_agent_changes`.
- `PATCH /my/account {city?, agency_name?}` — the agent's own directory details (§9.6).

### 9.6 Changing agent (`agent_change_requests`)

`id, customer_id, from_agent_id, to_agent_id, status ('pending'|'approved'|'rejected'|'cancelled'), note, created_at, decided_by, decided_at`.

- Directory for customers: `GET /customer/agents?q=&community_id=&city=` → active agents `{id, full_name, agency_name, city, phone, communities[], is_current}` (name/agency/city/phone are business details, shown to every active customer).
- `POST /customer/agent-change {to_agent_id, note?}` → `201` pending (`409 already_pending`, `400 same_agent`, `404 agent_not_found`). `POST /customer/agent-change/:id/cancel` while pending. `GET /customer/agent-change` → my requests, newest first.
- Only the **current agent** (or an admin) decides: `GET /agent-change-requests?box=outgoing|incoming` (`outgoing` = my clients asking to leave, these need my decision; `incoming` = customers moving to me, read-only), `POST /agent-change-requests/:id/approve | /reject`.
- Approve (one transaction): `customers.agent_id = to_agent_id`; `profiles.uploaded_by = to_agent_id` for the customer's profile; any other pending change request for the customer is cancelled. The old agent keeps nothing; the new agent sees the customer under Clients (already `active`) and the profile under My uploads. Pending contact/hold requests on the profile stay and are now decided by the new agent.

### 9.7 Profile fields added by the registration form

New columns (migration 005): `nationality_id → countries`, `birth_state`, `birth_country_id → countries`, `occupation_type_id → occupation_types` (new master: Private job, Government job, Business, Self-employed, Professional, Farmer / Agriculture, Student, Not working, Other), `other_income`, `work_country_id → countries`, `father_occupation`, `mother_occupation`, `elder_sisters`, `younger_sisters`, `elder_brothers`, `younger_brothers` (0–20), `property_share`, `property_details`, `customer_id`. The `countries` master now starts with **India** (sort 0) because nationality / birth / work / education countries all use it. New table `profile_education_levels (profile_id, level, details, country_id)` with `level` ∈ `below_10th | 10th | intermediate | graduation | post_graduation` — the form's education table; `educations` (highest qualification) and `education_details` ("other education details") stay.

On the wire: `education_levels: [{level, details, country: {id,name}|null}]` on reads; writes accept `education_levels` as a JSON array (or JSON string in multipart) of `{level, details?, country_id?}` — the set is replaced, `[]` clears. Master refs come back as `{id, name}` objects (`nationality`, `birth_country`, `work_country`, `occupation_type`).

`GET /masters` adds `occupation_types`; the admin master editor handles it like the other simple masters.

### 9.8 Visibility: "before approval" vs "on request"

The two hand-written sheets are the rule for **both** apps. Public ("Appearance profile"): photo, name, gender, marital status, age + DOB, birth time, religion, community, subcaste, gothram, mother tongue, complexion, food habit, education (highest + levels + details), profession / occupation type + details, package/income (+ other income), height, weight, nationality, languages known, NRI + country, **work country**, star/rasi, about.

On request — the PROTECTED set (§3.2), i.e. `PROTECTED_FIELDS` in `backend/src/lib/profiles.js`: `birth_place, birth_state, birth_country, work_place, nri_place, property_share, property_details, father_name, father_occupation, father_phone, mother_name, mother_occupation, mother_phone, contact_name, contact_phone, has_siblings, siblings_count, siblings_details, elder_sisters, younger_sisters, elder_brothers, younger_brothers, family_details, city, state`.

Who gets them: agents as before (uploader, admin, live contact approval); customers for their own profile always, and for another profile while their **accepted interest** is unexpired. List rows, shares, the card, the PDF and `/p/:token` never carry them; `work_country` / NRI country are the public location now (Mediator list cards show those instead of the work place). The Place filter still matches work place / NRI place / native city without revealing them.

### 9.9 Customer API (`/api/customer/*`, customer token)

Auth (`/customer/auth/*`, rate-limited like `/auth/*`): `otp/send`, `otp/verify`, `signup` (§9.3), `GET me` → `{customer: {id, full_name, phone, status, source, created_at, agent: {id, full_name, agency_name, phone, city, communities[]}, profile_id, pending_agent_change}}` (allowed while pending/suspended).

Allowed while **pending** (and active): `GET /customer/profile` (own, full incl. protected; `404 no_profile`), `POST /customer/profile` (multipart, same body as the agent form minus `status`; `409 profile_exists`), `PATCH /customer/profile` (JSON; `status` is ignored), `POST /customer/profile/photos`, `DELETE /customer/photos/:id`, `POST /customer/photos/:id/primary`, `GET /customer/photos/:id` (own photos plain; other visible profiles' photos **watermarked** with the agency label — customers never get clean copies of other people's photos).

Active only:
- `GET /customer/profiles` — same filters as the agent list minus `mine`/`status`. Scope: `status = 'active'`, `community_id IN (my agent's communities)`, `customer_id IS DISTINCT FROM me`, and `gender` defaults to the opposite of my profile's gender (`409 profile_required` until I have one; a `gender` param overrides). Rows are public fields + `interest_status` (my latest) and `is_interested`.
- `GET /customer/profiles/:id` — public fields + `interest: {id, status, days_left, access_expires_at}|null`; on-request fields only while accepted and unexpired. Uploader identity never.
- `POST /customer/profiles/:id/interest`, `POST /customer/interests/:id/withdraw`, `GET /customer/interests` → `{interests: [{id, status, created_at, decided_at, days_left, profile: {summary}}]}`.
- `GET /customer/agents`, `POST /customer/agent-change`, `POST /customer/agent-change/:id/cancel`, `GET /customer/agent-change` (§9.6).

### 9.10 Notifications (agents)

`GET /notifications` adds: `client_pending` (customer signups waiting for me), `interest_received` (pending interests on my uploads), `interest_decided` (decisions on my clients' interests), `agent_change_requested` (a client of mine wants to move — needs my decision), `agent_change_decided` (for the customer's new agent: "X is now your client"). `counts` gains `pending_clients`, `interests_inbox`, `agent_change_inbox`; the Clients tab badge = the sum of those three, and `badge` includes them.

### 9.11 Screens

**Mediator additions**
- Signup is two steps: mobile number → *Send OTP* → code entry (with the test-mode hint when `mock_code` is present) → the existing details form, submitted with the verification token.
- Bottom bar: **Profiles · Requests · Clients · Shortlists · More**. **Clients** has three tabs — *Clients* (pending first with Approve / Reject; active rows show the profile chip; tap → client detail with the profile link or "No profile yet", the client's interests with status / days left / the other agent's name, agency and phone with a call button, and any pending agent change), *Interests* (received on my uploads: customer's name + their agent's contact + the target profile; Accept / Decline; accepted shows days left + Revoke), *Transfers* (outgoing requests needing my Approve / Reject, incoming ones read-only). App-bar action **Registration form** → sheet with the link, Copy, Share on WhatsApp.
- Profile form: nationality, birth state + country, education levels (five rows: details + country), occupation type, other income, work country, father / mother occupation, siblings counts (elder/younger sisters/brothers), property share / details. The **on-request block** now holds native place, birth place/state/country, work place, parents, contact person, siblings, property, family details, all under the "visible only after approval" note.
- Profile detail: public cards drop work place, birth place, siblings and family details; the granted personal-details card gains birth place, work place, parents' occupations, siblings breakdown, property share / details, family details. List cards show NRI country / work country.
- Settings: **My city** (agent directory). Admin: **Customers** screen (list, activate / suspend / reject, reassign agent).

**Gandharva (customer app)**
1. Splash → **Mobile number** (logo, "Your agent's app for finding a match") → **OTP** (6 digits, resend after 30 s, test-mode hint) → new numbers: **Signup** (full name, agent's mobile number, "Ask your marriage bureau agent for their number") → **Waiting for approval** (agent's name / agency / phone with call button, *Complete your profile* button, pull-to-refresh, logout).
2. Home: **Browse · Interested · My profile · More**.
3. **Browse** — cards (photo, name, age, height, community · subcaste, education, profession); search by name; filter sheet (age, height, community — defaults to mine —, subcaste, education, profession, marital status, religion, mother tongue, food habit, complexion, NRI / country, place). Tap → **Profile** — photos carousel, before-approval fields grouped Personal / Education & Career / Horoscope / About, **I'm interested** button → pending banner "Your agent will follow up", accepted → *Details shared* card with the on-request fields + days left, declined / withdrawn states.
4. **Interested** — my interests with status chips; withdraw while pending.
5. **My profile** — none yet → the registration form in the paper's order (Basic → Birth → Community → Appearance → Education table → Professional → Family → Property → Photos); exists → view with Edit and photo management. Works while pending.
6. **More** — my agent card (name, agency, city, phone, communities; call button), **Change agent** → directory (search, community / city filters) → confirm → pending state with cancel; logout; version.

Strings live in `customer_app/lib/ui/strings.dart`. `API_BASE_URL` is the same `--dart-define` as Mediator (`customer_app/lib/config.dart`).

### 9.12 Guest mode, the ₹150 registration fee and up to 5 profiles (v2.2)

Replaces the parts of §9.2 / §9.3-A / §9.9 / §9.11 that say otherwise. A customer can now join with
just their mobile number and look around before committing.

**Account states.** `customers.status` gains **`guest`** and `customers.agent_id` becomes nullable
(NULL only while `guest`). Lifecycle: `guest` → (customer links an agent) `pending` → (agent/admin
approves) `active`; `reject` / `suspend` / `activate` as before. A `rejected` or still-`pending`
customer may link a different agent (it moves their profiles; the agent-change approval of §9.6 is
only for `active` customers).

**Access level** — computed, not stored: `access = 'full'` when `status = 'active'` **and** at
least one of the customer's profiles is paid; otherwise `'guest'` (suspended customers are blocked
as before). `GET /customer/auth/me` adds `access`, `max_profiles` (5), `profile_fee_inr` (150),
`payment_provider`, `profiles: [{id, full_name, gender, age, status, paid, paid_at, visibility, photo_url}]`
and an `unlock` checklist `{agent_linked, profile_registered, paid, approved}`. `profile_id` stays
(the oldest profile) for the v1.0 app.

**Signup (Gandharva).** Phone → OTP → new number → `POST /customer/auth/signup {full_name, phone,
phone_verification_token}` → `201` with `status: 'guest'`, no agent. (`agent_phone` is still
accepted; when present the account starts `pending` with that agent, as in v2.1.)

**Guest browsing.** Allowed for every non-suspended customer:
- `GET /customer/profiles` — scope with guest access: every `active` profile in **all**
  communities (never my own); full access keeps §9.9's scope (my agent's communities). Guest rows
  carry ONLY `{id, gender, age, community, subcaste, profession, occupation_type, income_text,
  primary_photo_url, locked: true}` — no name, no other field. Filters work the same, except that name search (`q`), the place
  filter (`city`) and `sort=name` are ignored for guests. `gender` has
  no default without a paid profile; with one it defaults to the opposite of the oldest paid
  profile's gender. The response says `access`.
- `GET /customer/photos/:id` — with guest access only the **primary** photo of an active profile,
  watermarked "Gandharva". Full access: every photo of a visible profile, watermarked with my
  agent's agency (unchanged).
- `GET /customer/profiles/:id`, `POST /customer/profiles/:id/interest`, `GET /customer/interests`
  and withdraw → `403 unlock_required` without full access.
- `GET /customer/agents` (the directory) is open to every non-suspended customer so a guest can
  pick an agent (`is_current` false when none); agent change (§9.6) still needs `active`.

**Linking an agent.** `POST /customer/agent {agent_phone}` or `{agent_id}` — allowed while
`guest`, `pending` or `rejected` (`409 wrong_status` otherwise — active customers use §9.6); the
agent must be active and have at least one community (`404 agent_not_found`, `400 agent_not_active`, `400 agent_has_no_communities`;
the directory lists only such agents), `400 same_agent` when already
pending with them). Sets `agent_id`, `status = 'pending'`, moves every profile of mine to that
agent (`uploaded_by`). The agent sees me under Clients → pending, with each profile's paid state.

**Up to 5 profiles per customer** (a parent registering several children, etc.). The unique index
on `profiles.customer_id` is dropped; `MAX_CUSTOMER_PROFILES = 5` (`409 profile_limit`). Creating
one needs a linked agent (`403 agent_required`) and status `pending` or `active`.
- `GET /customer/my-profiles` → `{profiles: [own view…], max_profiles, profile_fee_inr}`
- `POST /customer/my-profiles` (multipart, the §9.9 body) → `201 {profile}`
- `GET | PATCH | DELETE /customer/my-profiles/:id` (delete only while **unpaid**:
  `409 already_paid`), `POST /customer/my-profiles/:id/photos`
- The v1.0 routes `/customer/profile*` keep working on the oldest profile.
- Every own-profile view adds `paid`, `paid_at` and `visibility`:
  `'payment_pending' | 'awaiting_approval' | 'live' | 'hidden'`.

**The ₹150 registration fee** — one payment per profile (`PROFILE_FEE_INR`, default 150).
A customer profile is visible to others (status `active`) only when it is **paid AND the customer
is active**; until then it is stored `hidden`. Paying for a profile whose customer is active flips
it to `active`; approving a customer flips their *paid* hidden profiles to `active`. Agents cannot
set an unpaid customer profile to anything but `hidden`, nor share / download it (`409 payment_required`).
- `payments` table: `id, customer_id, profile_id, purpose ('profile_registration'), amount_paise,
  currency ('INR'), provider ('mock'|'razorpay'|'waived'), status ('created'|'paid'|'failed'),
  provider_order_id, provider_payment_id, created_at, paid_at`; `profiles.paid_at` mirrors the
  successful one.
- `POST /customer/my-profiles/:id/payment` → `201 {payment: {id, status, amount_inr,
  amount_paise, currency, provider, order_id, key_id}}` (`409 already_paid`).
- `POST /customer/payments/:id/confirm {provider_payment_id?, signature?, outcome?}` →
  `{payment, profile, customer}`. **mock** (`PAYMENT_PROVIDER=mock`, the default): nothing is
  charged; `outcome: 'failure'` records a failed attempt (to test the error path), anything else
  succeeds. **razorpay**: the order is created through Razorpay's Orders API (`RAZORPAY_KEY_ID`,
  `RAZORPAY_KEY_SECRET`) and confirm checks the checkout signature (HMAC-SHA256 of
  `order_id|payment_id` with the key secret) — `400 payment_verification_failed` otherwise. The
  Gandharva app ships only the mock checkout sheet; Razorpay also needs an app update with the
  Razorpay Checkout plugin, then the env switch.
- Customer profiles that exist when migration 006 runs are grandfathered as paid
  (`provider = 'waived'`).
- Agents: client rows gain `profiles[]` (summary + `paid`, `paid_at`); `profile` stays (the oldest).

**Interests with several profiles.** `customer_interests.from_profile_id` = which of my profiles
is interested. `POST /customer/profiles/:id/interest {from_profile_id?, note?}` — defaults to my
only live profile of the opposite gender; `400 from_profile_required` when there are several,
`400 no_matching_profile` when there is none. Agents' interest rows show that profile as
`customer_profile`, and only it (not every profile of the customer) becomes visible to the
target's uploader (§9.4).

**Gandharva screens (v1.1).** Phone → OTP → *Your name* → Home straight away (no waiting gate).
- Browse in guest mode: a banner "You are browsing as a guest — register to open profiles"; cards
  show photo, age, job, caste and package with a lock; tapping one opens the **Get started** sheet.
- **Get started** — the checklist: 1 Choose your agent (their mobile number, or pick from the
  directory) · 2 Register a profile · 3 Pay ₹150 · 4 Agent approval. Each open step has its
  button; done steps are ticked.
- **My profiles** tab (was My profile): up to 5 cards with a state chip (*Pay ₹150* /
  *Waiting for agent* / *Live* / *Hidden*), *Add profile*; tap → view / edit / photos / pay /
  delete (unpaid only).
- **Checkout** (mock): the amount, "Test mode — no money is charged", *Pay ₹150* and *Simulate
  failure*; success shows the profile's new state.
- Interested tab and profile detail need full access; *I'm interested* asks "On behalf of" when
  there is more than one matching profile.
- More: agent card or *Choose your agent*; change agent only when active.

### 9.13 Guest filters, deleting a paid profile, cash payments (v2.3)

Owner's corrections to §9.12 (2026-09-28). Where §9.12 says otherwise, this wins.

**Guests can filter.** Every browse filter works in guest mode, including the place filter
(`city`, which matches work place / NRI place / native city without revealing them) and every
sort except `name`. Only the name search (`q`) stays off for guests — a guest card has no name,
so searching by one would reveal it. The Gandharva filter sheet shows every filter to guests.

**Deleting a PAID profile needs the agent's approval** (an unpaid one is still deleted at once).
- `profile_delete_requests`: `id, customer_id, profile_id (SET NULL when gone), profile_name,
  status ('pending'|'approved'|'rejected'|'cancelled'), reason, created_at, decided_by, decided_at`;
  at most one pending per profile.
- Customer: `DELETE /customer/my-profiles/:id` on a paid profile → `409 approval_required`.
  `POST /customer/my-profiles/:id/delete-request {reason?}` → `201 {delete_request}`
  (`409 already_pending`; unpaid → `400 not_paid`, just delete it). `POST
  /customer/delete-requests/:id/cancel` while pending. Own-profile views carry
  `delete_request: {id, status, reason, created_at}|null` (the pending one).
- Agent (the customer's current agent) or admin: `GET /clients/delete-requests?status=`
  (default pending; agents see their clients', admins all) → `{delete_requests: [{id, status,
  reason, created_at, decided_at, profile_name, profile: summary|null, customer: {id, full_name,
  phone}}]}`; `POST /clients/delete-requests/:id/approve` → the profile is deleted for good
  (photos too; the payment row stays with `profile_id` NULL) and the request reads `approved`;
  `POST /clients/delete-requests/:id/reject`. `409 wrong_status` when not pending.
- Client rows: each `profiles[]` item gains `delete_request_id` (pending one or null); `GET
  /clients/:id` adds `delete_requests[]`.
- Notifications: `profile_delete_requested` (for the customer's agent; admins see all);
  `counts.delete_requests_inbox`; the Clients tab badge and `badge` include it.

**Paid in cash.** The customer's agent or an admin records an offline payment:
`POST /clients/:id/profiles/:profileId/mark-paid {note?}` → `{client}`. It writes a `payments`
row (`provider = 'cash'`, `status = 'paid'`, amount = the fee, `recorded_by` = the agent,
`note`), stamps `profiles.paid_at`, and puts the profile live when the customer is active — the
same effect as an in-app payment. `409 already_paid`, `404` when the profile is not that
client's. Mediator: *Mark paid (cash)* on each unpaid profile in the client detail (confirm
dialog). Gandharva shows it as paid like any other payment.

### 9.14 Mediator notifications screen (v2.4)

A **bell** in the Mediator app bar on every main tab, with a red count = `GET /notifications`
`badge` (things that need my action), opens **Notifications**: every `items[]` entry, newest first,
in two groups — **Needs your action** (`contact_request_received`, `hold_request_received`,
`client_pending`, `interest_received`, `agent_change_requested`, `profile_delete_requested`, and
for admins `agent_pending`, `password_reset_requested`) and **Updates** (everything else). Each
row: an icon per type, title, body, relative time ("5 min ago", "Yesterday"), and a dot on items
newer than the last time I opened the screen (a per-device timestamp in local storage — there is
no server-side read state in v1). Pull to refresh; the list also refreshes when the screen opens.
Tapping a row goes where the item can be acted on:

| type | opens |
|---|---|
| `contact_request_received`, `hold_request_received` | Requests tab → inbox |
| `contact_request_decided`, `hold_request_decided` | that profile (`profile_id`) |
| `community_request_decided` | My communities (settings) |
| `agent_pending` | Admin → Agents (pending) |
| `password_reset_requested` | Admin → Password resets |
| `client_pending`, `interest_decided`, `agent_change_decided`, `profile_delete_requested` | that client (`customer_id`) |
| `interest_received` | Clients → Interests |
| `agent_change_requested` | Clients → Transfers |

Unknown types (a newer backend) are listed but not tappable. No backend change: the screen uses
the existing endpoint.

### 9.15 Gandharva notifications (v2.5)

`GET /api/customer/notifications` (customer token; any status) → `{action_count, items[]}`,
items `{type, group ('action'|'update'), id, title, body, at, profile_id?, my_profile_id?, interest_id?}` — action items first, each group newest first
(decisions capped at the latest 30). Built from existing rows — no new table, no push (FCM is v2):

| type | group | when | taps to |
|---|---|---|---|
| `payment_due` | action | one per unpaid profile of mine | that profile of mine (Pay) |
| `interest_expiring` | action | my accepted interest ends within 3 days | that profile |
| `account_approved` | update | `approved_at` | My profiles |
| `account_rejected` | update | status rejected (`updated_at`) | Get started (pick another agent) |
| `interest_accepted` / `interest_declined` / `interest_revoked` | update | my interest decided | that profile |
| `payment_received` | update | a paid payment of mine (in-app or cash; not 'waived') | that profile of mine |
| `agent_change_approved` / `agent_change_rejected` | update | my change request decided by an agent | More (agent card) |
| `delete_request_approved` / `delete_request_rejected` | update | my delete request decided | My profiles / that profile |

`action_count` = number of action items. Bodies use profile names and "your agent" (the
customer's OWN agent may be named); never the uploader of another profile (CLAUDE.md rule 7).

**Gandharva screen:** a bell in the Browse / Interested / My profiles / More app bars with a count =
`action_count` + update items newer than the last time the screen was opened (per-device
timestamp); **Notifications** lists "Needs your action" then "Updates", icon per type, relative
time, "new" dot, pull to refresh, empty state; taps per the table (unknown types listed, not
tappable). Polled when the app comes to the foreground and every 60 s while open.

### 9.16 Push notifications (v2.6, Firebase Cloud Messaging)

Both apps get system push notifications for the same events as their Notifications screens
(§9.14 Mediator, §9.15 Gandharva). Firebase needs a project the owner creates; until its keys are
in the server `.env`, push is simply off and nothing else changes. **No app rebuild is needed to
switch it on:** the apps fetch the (public) Firebase client options from the backend at start-up.

**Config (env, see .env.example / ORACLE_SETUP):** `FCM_PROJECT_ID`, `FCM_API_KEY`,
`FCM_SENDER_ID`, `FCM_APP_ID_MEDIATOR`, `FCM_APP_ID_GANDHARVA` (the two Android apps registered in
that project: `com.matrimonyagents.matrimony_agents`, `com.matrimonyagents.gandharva`) and
`FCM_SERVICE_ACCOUNT` (the service-account JSON, base64-encoded) for sending.
`PUSH_PROVIDER` = `fcm` (default when the keys are present) | `log` (records pushes in memory —
tests) | `off` (default otherwise).

**API**
- `GET /api/push/config?app=mediator|gandharva` (public) → `{enabled, options: {api_key, app_id,
  messaging_sender_id, project_id}|null}` — `enabled` is false unless the provider is fcm/log and
  that app's id is set (log: dummy options).
- `push_devices` table: `id, token (unique), app ('mediator'|'gandharva'), agent_id | customer_id
  (exactly one), created_at, last_seen_at, cursor_at` (items newer than `cursor_at` are pushed).
- Agents (any status): `POST /api/push/devices {token}` → `201 {ok}` (upsert: a token moves to
  the latest account that registers it; `cursor_at = now()`), `POST /api/push/devices/remove
  {token}` on logout. Customers: the same under `/api/customer/push/devices`.
- Admin (tests / support): `POST /api/admin/push/run` runs one sender pass now →
  `{devices, sent}`; `GET /api/admin/push/outbox` (log provider only) → the last 200 recorded pushes
  `{app, agent_id?, customer_id?, title, body, data}`.

**Sender.** Every 60 s the API builds each registered owner's notification feed (the exact
functions behind `GET /notifications` / `GET /customer/notifications`) and pushes every item with
`cursor_at < at <= now()` — future-dated items (`interest_expiring`) and state reminders
(`payment_due`) are never pushed — at most 5 per device per pass (more → one "N new
notifications" summary), then moves the device's `cursor_at` to now. FCM HTTP v1, OAuth token from
the service account (signed locally, no Google SDK). A token FCM reports as unregistered is
deleted. Failures are logged, never surfaced to API callers.

**Payload.** `notification: {title, body}`, `android: {priority: high, notification: {channel_id:
'updates'}}`, `data` (strings): `type, id, app` + `profile_id, customer_id, my_profile_id,
interest_id` when present. Titles/bodies are the feed's — the same privacy rules apply (a
customer never learns another profile's uploader). Push content passes through Google's servers.

**Apps.** At start-up after login: fetch `/push/config`; if enabled, initialise Firebase with those
options, ask for the notification permission (Android 13+), get the FCM token, register it (and
again on token refresh); on logout remove it. Foreground message → refresh the notifications
state and show a small in-app banner; tapping a system notification (background or terminated)
opens the app on the item's target using the same routing as the Notifications screen (falls
back to the Notifications screen). Android channel `updates` ("Updates", high importance).

## 8. Explicit v2 (do NOT build now)
iOS build, Telugu/Hindi UI, horoscope matching/compatibility scores, in-app chat, AI import of old WhatsApp chat exports, real SMS OTP provider wiring beyond the `msg91` adapter (configure by env once the subscription exists).
