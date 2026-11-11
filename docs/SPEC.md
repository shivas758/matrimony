# Wedbook (Matrimony Agents) — Full Specification

Since v2.8 (§9.18) the product is **Wedbook**: the agents' app is **Wedbook Agent** (called *Mediator* until v2.7) and the customers' app is **Wedbook Matrimony** (*MILI* until v2.7, *Gandharva* before that). Older sections still say Mediator / MILI / Gandharva — read them as the two Wedbook apps; "Mediator" and "Gandharva" remain the internal code names. The Android package ids stay `com.matrimonyagents.matrimony_agents` and `com.matrimonyagents.gandharva` so existing installs update in place.

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

Testing: `cd backend && npm run smoke` runs 1525 end-to-end assertions (46 steps) against a live
API, covering every rule in §3, §9 and CLAUDE.md (steps 42–46 cover §9.18: agent codes per state
and the once-only State choice, customer / profile IDs and who may see them, the privacy toggles
in lists, filters, shares, photos, request rows and notifications, the community audience, and the
four-step registration form; steps 24–27 cover birth details, the hold
workflow, delete, and religion / languages / food habit / siblings + the PDF share; steps 28–36
cover OTP hardening, customer signup and pending gating, the Clients routes, the customer browse
scope, interests end to end, agent change, the public registration form, the §9.7 fields and admin
customers; step 37 pins the review fixes — shortlist rows carry no protected field, suspended customers cannot edit their profile, revoking an interest also revokes the auto-granted contact access, bad query/file input answers 400). Each step rotates an `X-Forwarded-For` so the auth rate limiter does not trip.
`npm run seed:demo` fills the database with 2 communities, 3 agents, 12 profiles and 6 Gandharva
customers (OTP `123456`) for app development. `cd app && flutter test` and
`cd customer_app && flutter test` cover the models and filter serialisation.

## 9. Customers, the MILI app (formerly Gandharva), OTP signups (v2.1; guest mode and fee: §9.12, v2.2; guest filters, delete requests, cash: §9.13, v2.3; MILI rebrand, photo editor, one profile per customer: §9.17, v2.7)

Two apps now share one backend:

| App | Users | Package | Directory |
|---|---|---|---|
| **Mediator** (existing) | agents + admins | `com.matrimonyagents.matrimony_agents` | `app/` |
| **MILI** — "MILI Matrimony" (was *Gandharva* until v2.7) | customers (the brides/grooms or their families) | `com.matrimonyagents.gandharva` | `customer_app/` |

A **customer** is always attached to exactly one **agent**. Customers never talk to each other or to
other agents directly: they browse, mark *interested*, and their agent (or the other party's agent)
does the rest by phone. Logo and palette: see §9.17 (MILI); the paragraphs below still say
"Gandharva" where they were written before the rename — read it as MILI. Type: Poppins +
Playfair Display, same files as Mediator.

### 9.1 OTP (mock now, real SMS later — Firebase phone auth since v2.9, §9.19 A)

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

### 9.12 Guest mode, the ₹150 registration fee and up to 5 profiles (v2.2; one profile since v2.7, §9.17)

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
  Razorpay Checkout in the app, capture, the safety net and the webhook: §9.19 B (v2.9).
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

### 9.17 MILI rebrand, photo editor + camera, one profile per customer (v2.7)

Owner's requests of 2026-10-19. Where earlier sections say otherwise, this wins.

**The customer app is now MILI** ("MILI Matrimony"; logo `new logo/MILI logo.jpeg`: two gold
interlocked rings forming an "m", the wordmark MILI in wine and MATRIMONY beneath, on a cream tile
with a peach glow). The rename is what people see, not the plumbing: the package id
`com.matrimonyagents.gandharva`, the directory `customer_app/`, the Dart package `gandharva`, the
push app key `gandharva` (`/push/config?app=gandharva`, `FCM_APP_ID_GANDHARVA`) and the token
`typ` all stay, so the installed Gandharva app updates in place to MILI and customers stay logged
in. "Gandharva" remains the internal code name in code comments. Everything a person reads says
MILI: launcher label, splash, in-app wordmark, the watermark on guest photos, the registration
form `/r/:token`, OTP/notification texts, and Mediator texts that mention the customers' app.
- **Icon / logo** (`customer_app/tool/gen_logo.mjs`, source `customer_app/assets/logo/mili_source.jpg`):
  the launcher icon is the rings + MILI on the cream tile (MATRIMONY is unreadable at icon size and
  is dropped); the splash shows the full logo; in-app, `AppLogo` shows the full logo on its cream
  tile (it reads on both the cream pages and the wine headers).
- **Palette** (sampled from the logo; `AppColors` in `customer_app/lib/ui/theme.dart`, mirrored
  in the registration form): wine `#6A1B2D` (primary) / deep wine `#3F0E1A` / light wine `#8C2D44`,
  gold `#C8A056` / dark gold `#94702F` (gold text and icons on light backgrounds, 4.5:1 on white) / light gold
  `#F4E6C4`, peach `#FED4C4`, on cream `#FFF8EE` (deeper cream `#FBEEDB` for chips and panels).
  Mediator keeps its navy/gold palette.

**Photo editor + camera (both apps).** Wherever photos are added — Mediator add/edit profile;
MILI registration form and My profile → photos — *Add photos* opens a sheet: **Take photo**
(camera) or **Choose from gallery** (multi-select, up to the free slots of the 8). Each new photo
then opens the **editor**: crop and rotate, free-form, starting on a portrait 4:5 frame with
Original / Square / 3:4 / 4:5 / 16:9 presets. Cancelling the editor keeps the photo as taken.
Until the form is saved every new photo's thumbnail has **Edit** (re-open the editor) and
**Remove**. What leaves the phone is the edited image; the server is unchanged (JPEG, longest
side ≤ 1280 px, never cropped). Android: `image_picker` (camera source) + `image_cropper` (uCrop).

**Photos are never cut on a profile page.** The profile detail screen in both apps shows each
photo whole — fitted inside the header over a blurred, enlarged copy of itself — and tapping it
opens a full-screen viewer (swipe between photos, pinch to zoom). The public share page
`/p/:token` does the same. List cards still fill their frame (a grid needs one shape) but anchor
on the upper part of the photo so faces stay in view.

**Fixed with this release.** (1) Watermarked copies (`/p/:token` photos, the customer photo route
for other profiles, the PDF bio-data's photos) failed with a 500 for every stored photo larger than 1080 px
— the overlay was sized from the input instead of the resized image (`lib/photos.js`). The smoke
test's sample photo is now 960 × 1280 so the suite covers it. (2) Choosing the gallery with exactly
one free photo slot crashed (`pickMultiImage` needs a limit of at least 2); it now picks one photo.

**One profile per customer.** Replaces §9.12's "up to 5": a customer registers exactly one
profile (for one bride or groom). `max_profiles` is 1 everywhere it is reported; creating a second
→ `409 profile_limit` ("You can register only one profile"). Enforced in the database too by
migration 009: a partial unique index `uq_profiles_one_per_customer ON profiles(customer_id)
WHERE customer_id IS NOT NULL` (skipped with a NOTICE if duplicates already exist — there were
none on 2026-10-19 — and a concurrent second insert maps to the same 409). The env knob
`MAX_CUSTOMER_PROFILES` is gone. The multi-profile API shapes stay (`profiles[]`,
`/customer/my-profiles`, `from_profile_id`) so older app builds keep working. Deleting the profile
(unpaid directly, paid via the §9.13 delete request) frees the slot for a new one.
- **MILI**: the *My profiles* tab is **My profile** again. No profile → the *Create your profile*
  call to action (Get-started step 2 unchanged); one profile → that profile's page right in the tab
  (view, edit, photos, pay, delete). The "On behalf of" chooser can no longer appear.
- **Mediator**: client screens show the client's single profile; texts that said "up to 5" are
  gone.
- The registration form `/r/:token` already creates exactly one profile with the account; its
  "already registered" page now points to *My profile* in MILI.

### 9.18 Wedbook: rebrand, agent codes, customer IDs, privacy toggles, community audience, four-step forms (v2.8)

Owner's requests of 2026-11-09. Where earlier sections say otherwise, this wins.

#### A. Names and logos

| | until v2.7 | now | package (unchanged) | APK |
|---|---|---|---|---|
| agents' app (`app/`) | Mediator | **Wedbook Agent** | `com.matrimonyagents.matrimony_agents` | `wedbook-agent-v3.0.0.apk` |
| customers' app (`customer_app/`) | MILI | **Wedbook Matrimony** | `com.matrimonyagents.gandharva` | `wedbook-matrimony-v3.0.0.apk` |

The rename is what people see, not the plumbing: package ids, directories, Dart package names, the
push app keys (`mediator` / `gandharva`, `FCM_APP_ID_*`) and the token `typ` all stay, so both apps
update in place and everyone stays logged in. Everything a person reads says Wedbook: launcher
labels, splash, wordmarks, share card / PDF / `/p/:token` ("Wedbook"), the registration form
`/r/:token` ("Wedbook Matrimony"), the default photo watermark ("Wedbook"), notification texts.

- **Logos** (`new logo/WhatsApp Image 2026-10-28 at 08.56.03.jpeg` = Matrimony, `…08.56.27.jpeg` =
  Agent): a rounded tile — wine for Matrimony, royal blue for Agent — with two interlocked gold
  rings holding the ♂ and ♀ signs and the gold serif wordmark "Wedbook / Matrimony" or
  "Wedbook / Agent". Copied to `customer_app/assets/logo/wedbook_matrimony_source.jpg` and
  `app/assets/logo/wedbook_agent_source.jpg`; each app's `tool/gen_logo.mjs` cuts the tile out of
  the white canvas and renders the in-app logo, launcher icons (legacy + adaptive) and splash.
  The launcher icon is the supplied artwork itself — rings and wordmark on the tile colour (the
  adaptive icon keeps both inside the safe zone on a full-bleed background of the tile colour);
  in-app and on the splash the same tile is shown.
- **Palettes** (sampled from the tiles). Wedbook Agent: blue `#043270` / deep `#021E4A` / light
  `#0D4A9A` replace the navy family; gold unchanged (`#C9962E`, light `#E8C25F`); ivory ground
  unchanged. Mirrored in the backend share card, PDF and `/p/:token`. Wedbook Matrimony: wine
  `#540729` / deep `#3A0419` / light `#7A1B45` replace the MILI wine family; gold (`#C8A056`, dark
  `#94702F`, light `#F4E6C4`) and the cream ground unchanged. Mirrored in `/r/:token`.

#### B. Agent codes

Every agent gets a permanent code: **STATE CODE + NUMBER + LETTER(S)**, numbered separately per
state in the order the codes are issued:

`KA1A, KA1B … KA1Z, KA2A … KA2Z, … KA999A … KA999Z`, then two letters `KA1AA, KA1AB … KA1ZZ, KA2AA …
KA999ZZ` (then three letters, should a state ever need it). No zero padding.

- New master **`states`** `(id, name, code, active, sort_order)`: the Indian states and union
  territories with their two-letter codes (KA Karnataka, AP Andhra Pradesh, TS Telangana, TN Tamil
  Nadu, KL Kerala, MH Maharashtra first, the rest alphabetically). `GET /masters` adds
  `states: [{id, name, code, active, sort_order}]`. Codes are fixed once a state exists: the admin
  master API can rename, re-order and deactivate a state (`PATCH /admin/masters/states/:id`), not
  re-code it; `POST /admin/masters/states {name, code}` adds one. The list is complete for India,
  so Wedbook Agent's master editor has no States tab (API only).
- `agents.state_id → states`, `agents.agent_code` (unique). The per-state counter lives in
  `agent_code_counters (state_id, last_seq)` and only ever counts up, so a code is **never reused**,
  also not after an agent is deleted. A code never changes once given, and neither does the state.
- **New agents** choose their State on the signup form: `POST /auth/signup {…, state_id}`
  (`400 invalid_state`); the code is generated in the same transaction (so pending agents already
  have one). `state_id` stays optional in the API for app builds older than 3.0.0.
- **Agents registered before v2.8** have no state: the first time they open Wedbook Agent 3.0.0 a
  full-screen **Choose your State** step asks once (with a "this cannot be changed later"
  confirmation) → `POST /my/state {state_id}` → `{agent}` (`409 state_already_set`,
  `400 invalid_state`). Codes are issued in the order agents complete this step.
- The agent object (`/auth/login`, `/auth/me`, `/auth/signup`, `/my/account`, `/my/state`) adds
  `state: {id, name, code} | null` and `agent_code: string | null`.
- **Searchable.** `GET /admin/agents?q=` also matches the code (rows add `agent_code`,
  `state: {id, name, code}|null`); the customers' directory `GET /customer/agents?q=` matches it
  too. A customer can link their agent by code: `POST /customer/agent {agent_code}` (as well as
  `agent_phone` / `agent_id`; `404 agent_not_found`).
- **Who sees an agent's code:** the agent, admins, customers in the directory and on their "my
  agent" card (`agentDirectory` adds `agent_code`), and the other agent in an interest or
  agent-change row (those cards add `agent_code`). It is never printed on a profile, a share page
  or a PDF.

#### C. Customer / profile IDs

Every profile gets a permanent ID: **`GN-<agent code>-<letter><3 digits>`**, numbered per agent:
`GN-KA1A-A001 … GN-KA1A-A999, GN-KA1A-B001 … GN-KA1A-Z999` (then two letters `AA001…`). With one
profile per customer (§9.17) this is the customer's ID.

- `profiles.profile_code` (unique, nullable); the per-agent counter is `agents.profile_seq` (only
  counts up — never reused).
- Assigned when the profile is created, from its agent (`uploaded_by`) — agent uploads, customer
  registrations in the app and the web form alike. A profile whose agent has no code yet gets its
  ID when that agent chooses their State (all of that agent's profiles then, oldest first), or when
  the customer links / is moved to an agent who has one.
- **Permanent**: once assigned it never changes — not on an agent change either (the ID keeps
  showing the agent who first registered the customer).
- **Owner side only.** The ID contains the agent's code, so it follows the uploader-identity rule
  (CLAUDE.md rule 3 / 7): `profile_code` is sent only to the profile's own agent (uploader), admins
  and the owning customer. Other agents, other customers, guest cards, share texts, the photo card,
  the PDF and `/p/:token` never carry it.
- Where it appears: profile list rows / detail / write responses for the owner side
  (`profile_code`); embedded profile summaries shown to the owner side (client rows `profile` /
  `profiles[]`, interest rows for the side that owns that profile, delete requests); the
  customer's `me` (`customer_code` = their profile's ID or null, and `profiles[].profile_code`);
  client rows (`customer_code`).
- **Searchable** by the owner side: `GET /profiles?q=` matches the ID on the caller's own uploads
  (admins: any profile) in addition to the name; `GET /clients?q=` and `GET /admin/customers?q=`
  match it too.

#### D. Privacy toggles — what a profile shows

A customer decides, detail by detail, what others see. **Always shown** (not switchable): the main
photo, age and gender. Everything else on the "before approval" sheet (§9.8) has a toggle:

| section | key | hides (API keys) |
|---|---|---|
| personal | `name` | `full_name` (replaced, see below) |
| personal | `dob` | `dob` (age stays) |
| personal | `marital_status` | `marital_status` |
| personal | `religion` | `religion` |
| personal | `community` | `community` **and** `subcaste` |
| personal | `subcaste` | `subcaste` |
| personal | `mother_tongue` | `mother_tongue` |
| personal | `known_languages` | `known_languages` |
| personal | `height` | `height_cm` |
| personal | `weight` | `weight_kg` |
| personal | `complexion` | `complexion` |
| personal | `food_habit` | `food_habit` |
| personal | `nationality` | `nationality` |
| personal | `about` | `about` |
| personal | `photos` | every photo except the main one |
| professional | `education` | `education`, `education_details`, `education_levels` |
| professional | `profession` | `profession`, `profession_details`, `occupation_type` |
| professional | `income` | `income_text`, `other_income` |
| professional | `work_location` | `work_country`, `is_nri`, `nri_country` |
| horoscope | `star_rasi` | `nakshatram`, `zodiac` |
| horoscope | `gothram` | `gothram` |
| horoscope | `birth_time` | `birth_time` |

The list is served by the API — `GET /masters` adds `privacy_fields: [{key, label, section, hint}]`
(`section` ∈ `personal | professional | horoscope`, `hint` a short note or null) and
`privacy_always_visible: ['Main photo', 'Age', 'Gender']` — the apps render the toggles from it.

- Stored as `profiles.hidden_fields TEXT[]` (default `{}` = everything shown, today's behaviour).
- **Write**: the body key `hidden_fields` (JSON array, or a comma-separated / JSON string in
  multipart; `[]` shows everything; an unknown key → `400 validation_failed`) on
  `POST | PATCH /customer/my-profiles[/:id]`, `/customer/profile`, and — the agent acting for the
  family — `POST | PATCH /profiles[/:id]` (uploader or admin). The web form `/r/:token` has no
  toggles (everything shown until the customer or agent changes it).
- **A switched-off detail is "on request"**: it is revealed exactly when the §9.8 on-request block
  is — to the uploader, admins, an agent with an unexpired approved contact request, the owning
  customer, and a customer whose interest is accepted and unexpired (15 days). For everyone else
  the value is `null` (`[]` for lists, `false` for `is_nri`), and:
  - `full_name` becomes the neutral label **`Profile <id>`** (the numeric profile id — never the
    ID of §C) so every screen still has something to show;
  - `masked_fields: [keys…]` on every profile object lists what was withheld from this viewer
    (`[]` when nothing was), so the apps can say "some details are shared after approval";
  - `photos` / `primary_photo_url` carry only the main photo, and the photo routes refuse the
    others (`404 photo_not_found`).
- **Everything that leaves the app is always masked**, whoever shares it — the WhatsApp summary,
  the photo card, the PDF and `/p/:token` (and its photo route) never show a switched-off detail,
  also not when the uploader shares their own profile (same rule as the on-request fields, §3.3).
- **List rows** are masked the same way; the caller's own uploads (admins: all) and profiles the
  caller currently has contact access to (agents: approved request; customers: accepted interest)
  come unmasked. Guest cards (§9.12) drop a hidden community, subcaste, job or package.
- **Filters never leak a hidden value**: a filter on a hidden detail does not match that profile
  for other viewers (community / subcaste / education / profession / occupation type / marital
  status / complexion / religion / mother tongue / languages / food habit / star / rasi / height /
  NRI / country / work country; name search and name sort likewise) — the caller's own uploads
  still match (admins: everything). Age, gender and the place filter are unaffected.
- **Names elsewhere.** Wherever a profile's name is shown to someone without access it is the
  neutral label: shortlist rows, the *sent* box of contact / hold requests, interest rows (the
  other side's profile, and that customer's account name), notifications and pushes. Rows that
  embed a profile summary add `name_hidden: true` when that happened.
- The owner side also gets the setting back: `hidden_fields: [keys…]` on the profile object
  (uploader, admin, owning customer only).

#### E. Community audience — who a profile is shown to

By default a profile is shown to its own community, as before. The customer can widen that:

- `profiles.audience_all BOOLEAN` (default false) and `profiles.audience_community_ids INT[]`
  (default `{}`): **additional** communities the profile is shown to. The profile's own community
  is always part of the audience (it is implicit and never stored in the list).
- **Write**: `audience_all` (true/false) and `audience_community_ids` (id list like
  `known_language_ids`; unknown id → `400 invalid_reference`; the own community is dropped) on the
  same routes as `hidden_fields`. The owner side reads back `audience_all` and
  `audience_communities: [{id, name}]`.
- **Visibility (replaces "community in the agent's communities" in §3.1 and §9.9).** Let
  `shown_to(P, C)` = `P.community ∈ C OR P.audience_all OR P.audience_community_ids ∩ C ≠ ∅`.
  - Agents see active profiles with `shown_to(P, the agent's communities)` (own uploads, the hold
    and interest branches unchanged; admins everything).
  - Customers with full access see active profiles whose community is in their agent's
    communities (as before) **or** with `P.audience_all` **or** whose audience list contains the
    community of the customer's own profile.
  - Guest cards (§9.12) are unchanged: a teaser of every active profile.
- "No caste preference": hide `community` and switch on *All communities*.

#### F. Four-step profile forms

The profile form is four sections instead of one long page — the same four in Wedbook Matrimony
(register / edit my profile), Wedbook Agent (add / edit profile) and the web form `/r/:token`:

1. **Personal details** — (web form: your mobile number) name, gender, date of birth, marital
   status, religion, community, subcaste, mother tongue, languages known, height, weight,
   complexion, food habit, nationality, about, photos.
2. **Professional details** — the education table (five levels), highest qualification, other
   education details, occupation type, profession, profession details, income, other income, work
   country, work place*, NRI + country + place*.
3. **Horoscope** — star (nakshatram), rasi, gothram, birth time, birth place*, birth state*,
   birth country*.
4. **Family & contact** — father and mother (name, occupation, phone)*, siblings*, family
   details*, property share / details*, native place (city, state)*, contact person (name,
   phone)*.

(* = on request, §9.8 — marked "visible only after approval" as before.)

A step header shows the four steps with the current one highlighted; **Back** / **Next** move
between them and **Next** validates the current step (required: name, gender, date of birth,
community — all in step 1). The last step's button saves. When editing an existing profile every
step is reachable by tapping its header and **Save** is available on every step. Nothing is sent
until Save; leaving with unsaved changes asks first. The web form keeps working without
JavaScript (all four sections stacked, one submit button) and gains star / rasi selects for its
Horoscope section.

#### G. Screens

**Wedbook Agent** (3.0.0)
- Signup: a required **State** dropdown ("decides your agent code — cannot be changed later").
  The pending screen and Settings show **Your agent code** (tap to copy).
- **Choose your State** gate for agents without a code (after the set-password gate, before Home).
- Profile cards, profile detail, My uploads and client screens show the **ID** on the owner side
  (tap to copy on the detail screen). The profile search box says "Search by name or ID".
- A profile with `masked_fields` shows a lock note on its detail screen: "Some details are hidden
  by the family — they are shared when your contact request is approved."
- Add / edit profile: the four steps (§F); the AI import, status and photo editor stay. The last
  step ends with a **Privacy** card: the toggles of §D grouped by section, and "Show this profile
  to" (own community only / selected communities / all communities) of §E.
- Admin → Agents: the code on each row, search by code. Interest and transfer rows show the other
  agent's code.

**Wedbook Matrimony** (3.0.0)
- My profile shows **Your ID** (tap to copy) once assigned; the agent card shows the agent's code.
- Get started → *Choose your agent*: one field takes the agent's **mobile number or agent code**;
  directory rows show the code and search matches it.
- Register / edit profile: the four steps (§F).
- **Privacy** (My profile → *Privacy settings*; also opened once right after a profile is
  created): "Always shown: main photo, age, gender", then the toggles of §D grouped Personal /
  Professional / Horoscope ("Shown to everyone" ↔ "Only after approval"), then **Show my profile
  to**: *My community only* · *Selected communities* (multi-select) · *All communities*. Save →
  `PATCH /customer/my-profiles/:id {hidden_fields, audience_all, audience_community_ids}`.
- Browse / profile detail: a masked name arrives as "Profile 1042"; a profile with `masked_fields`
  shows "Some details are hidden — they are shared after your interest is accepted."

#### H. Assumptions (not confirmed by the owner)

- The fourth form section is "Family & contact"; photos sit in step 1.
- State codes follow the vehicle-registration letters; Telangana is **TS** as written.
- The customer ID prefix stays **GN** although the app is no longer called Gandharva; the digits
  start at 001 (`A000` is not used).
- Agent-uploaded profiles (no customer account) get an ID too, and their agent can set the privacy
  toggles and the audience for the family.
- Admins are agents: they choose a State and get a code like everyone else.
- Guest teaser cards still show every active profile regardless of the audience setting (§9.12).

### 9.19 Real OTP through Firebase phone auth, Razorpay checkout (v2.9)

The owner asked to switch the mock OTP to **Firebase phone authentication** and the mock fee to
**Razorpay**; after hearing that Firebase SMS is Blaze-only (≈ ₹6 per SMS after ~10 a day) they
chose **Fast2SMS** for OTP instead (C) — Firebase stays built in as a dormant alternative. All
stay env switches on the server: with no keys, everything behaves exactly as before (mock OTP
`123456`, mock checkout). Apps: **Wedbook Agent 3.1.0+13**, **Wedbook Matrimony 3.1.0+8**
(`wedbook-agent-v3.1.0.apk`, `wedbook-matrimony-v3.1.0.apk`).

#### A. OTP provider `firebase`

With `OTP_PROVIDER=firebase` the **phone** sends and receives the SMS through Firebase
Authentication; the server sends no SMS, stores no code, and instead verifies the **Firebase ID
token** the app gets once the code is accepted. The rest of §9.1 (verification token, signup,
customer login answer) is unchanged.

- **Config:** `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`, `FIREBASE_SENDER_ID`,
  `FIREBASE_APP_ID_AGENT`, `FIREBASE_APP_ID_CUSTOMER` — the same Firebase project and the same two
  Android apps as push (§9.16); each falls back to its old `FCM_*` name (`FCM_PROJECT_ID`,
  `FCM_API_KEY`, `FCM_SENDER_ID`, `FCM_APP_ID_MEDIATOR`, `FCM_APP_ID_GANDHARVA`). Push additionally
  needs `FIREBASE_SERVICE_ACCOUNT` (old name `FCM_SERVICE_ACCOUNT`); OTP does not.
- **Send** — `POST /auth/otp/send {phone, firebase?}` (agent signup) and
  `POST /customer/auth/otp/send {phone, firebase?}`. New apps send `firebase: true` ("I can do
  Firebase"). Every send response now carries `provider` (`mock` | `msg91` | `firebase`).
  - provider `firebase` + `firebase: true` → `200 {sent: false, provider: 'firebase', mock: false,
    expires_in: 300, retry_after: 30, firebase: {api_key, app_id, messaging_sender_id,
    project_id}}` — the options for *that* app (agent route → agent app id, customer route →
    customer app id). Nothing is stored; the agent route still answers `409 phone_taken` first.
  - provider `firebase` + an older app (no flag) → `426 app_update_required` "Please update the
    app to get your code" (the 3.0.0 apps show the server message).
  - provider `firebase` but an option is missing → `503 otp_provider_error`.
  - `mock` / `msg91`: unchanged (the flag is ignored).
- **Verify** — the same two `…/otp/verify` routes accept `{phone, firebase_id_token}` instead of
  `{phone, code}`. The server checks the token itself (no Google SDK): RS256 signature against
  Google's published `securetoken@system.gserviceaccount.com` certificates (cached per their
  `Cache-Control`), `aud` = project id, `iss` = `https://securetoken.google.com/<project id>`,
  not expired, `auth_time` within the last 15 minutes, a `sub`, and `phone_number` =
  `+91<phone>`. Then it answers exactly like a code verify (agent: `{verification_token}`;
  customer: login or `{new: true, verification_token}`).
  Errors: `400 invalid_firebase_token` (bad / expired / other project / not a phone sign-in),
  `400 phone_mismatch` (token is for another number), `400 otp_provider_mismatch` (a token while
  the provider is not firebase, or a code while it is), `503 otp_provider_error` (certificates
  unreachable).
- **Limits:** Firebase's own (per number, per IP, per device; app verification through Play
  Integrity, falling back to a reCAPTCHA page for APKs installed outside the Play Store). The
  `otp_codes` throttles keep applying to mock / msg91 only.
- **Apps** (both): on a `firebase` send response → initialise Firebase with those options (unless
  push already did — same project), `verifyPhoneNumber('+91<phone>')`. Android may verify by
  itself (instant verification / SMS auto-read) — then the app continues without typing;
  otherwise the user types the 6-digit code → `signInWithCredential` → `getIdToken()` → verify
  call → `FirebaseAuth.signOut()` (the app keeps no Firebase session; our JWT is the session).
  Resend after 30 s with the `forceResendingToken`. Firebase errors become plain messages
  (wrong code, code expired, too many attempts, invalid number, network, "phone verification is
  not set up" for configuration errors). No "Test mode" hint in firebase mode.
- **Owner setup** (deploy/ORACLE_SETUP.md): Firebase project on the **Blaze** plan (phone-auth SMS
  is Blaze-only: about 10 SMS/day free, then a per-SMS charge for India), Authentication → Phone
  enabled, both Android apps registered with the SHA-1 and SHA-256 of the key that signs the APKs,
  SMS region policy "allow India only", optional test numbers. **Switch only after the 3.1.0 APKs
  are out** — 3.0.0 apps cannot do Firebase OTP.

#### B. Razorpay checkout

- **App** (Wedbook Matrimony 3.1.0, `razorpay_flutter`): when `payment_provider == 'razorpay'`,
  *Pay* creates an order (`POST /customer/my-profiles/:id/payment`, as before) and opens Razorpay
  Checkout with `{key: payment.key_id, order_id, amount: amount_paise, currency: 'INR', name:
  'Wedbook Matrimony', description: 'Profile registration fee', prefill: {contact: '+91<phone>'}}`.
  Success → `POST /customer/payments/:id/confirm {provider_payment_id, signature}`. Cancel / error
  → a message, no confirm call; trying again starts a new order. No "Test mode" card and no
  *Simulate failure* button for razorpay. The mock checkout is unchanged.
- **Confirm:** signature check as in §9.12; then the server makes sure the money is **captured**:
  it fetches the payment and captures it when Razorpay still shows it `authorized` (accounts set
  to manual capture would otherwise auto-refund after a few days). A capture problem is logged,
  never shown to the customer.
- **Safety net for an app that died after paying:** before creating a new order, the server asks
  Razorpay about this profile's earlier open razorpay orders (`created` / `failed`); an order
  Razorpay reports `paid` is settled → `409 already_paid` (the app already treats that as done).
- **Webhook** `POST /api/payments/razorpay/webhook` (public; `X-Razorpay-Signature` =
  HMAC-SHA256 of the raw body with `RAZORPAY_WEBHOOK_SECRET`): events `order.paid` and
  `payment.captured` settle the payment with that `provider_order_id`. `200 {ok}` for any
  correctly signed event (unknown orders / events are ignored), `400 invalid_signature`,
  `503` when no webhook secret is set. Optional but recommended.
- **Settling** (confirm, safety net, webhook — one code path): payment `paid`, `profiles.paid_at`,
  profile live when the customer is active (§9.12). If the profile was **already paid** by another
  payment (rare: a slow UPI payment completing after a retry was paid) the row becomes
  `status = 'refund_due'` with a note — refund it from the Razorpay dashboard; the admin
  dashboard counts them (`refunds_due`).
- **Migration 011:** `payments.status` gains `refund_due`; unique index on the razorpay
  `provider_order_id`.
- **Test hooks** (never set in production): `RAZORPAY_API_BASE` (default
  `https://api.razorpay.com/v1`), `FIREBASE_CERTS_URL` (default Google's certificate URL) and
  `FAST2SMS_API_URL` (default `https://www.fast2sms.com/dev/bulkV2`) let
  `backend/test/providers.mjs` run the flows against local fakes.

#### C. OTP provider `fast2sms` (the owner's choice)

`OTP_PROVIDER=fast2sms` + `FAST2SMS_API_KEY`. Works exactly like `msg91` (§9.1): the server
generates the 6-digit code, stores its hash, sends it, and the apps' existing code screens verify
it — so it works with **every app version** (3.0.0 included); no app update is needed for OTP.

- Send: `POST https://www.fast2sms.com/dev/bulkV2`, header `authorization: <key>`, JSON
  `{route: 'otp', variables_values: '<code>', numbers: '<10 digits>', flash: 0}`. Fast2SMS
  delivers its fixed OTP text ("Your OTP: <code>" style) through its DLT-registered OTP route —
  no DLT registration of our own. Success = HTTP 200 with `return: true`; anything else (HTTP
  error, `return: false` with a `status_code`/`message`, unreachable) is logged and answered
  `503 otp_provider_error` "Could not send the SMS — try again in a minute"; nothing is stored,
  so the resend cooldown is not used up.
- The send response is the §9.1 shape with `provider: 'fast2sms'`, `mock: false`, no
  `mock_code`. The `firebase: true` flag of the 3.1.0 apps is ignored.
- Owner setup: Fast2SMS account, **website verification** in the panel's *OTP Message* menu (error
  996 "Before using OTP Message API, complete website verification" otherwise — what production got
  on 2026-11-11, so it went back to mock), possibly a first wallet recharge of at least ₹100 (error
  999), API key from *Dev API*. The key is already in the production `.env`; switching on =
  `OTP_PROVIDER=fast2sms` + `docker compose up -d`. Throttles (30 s between sends,
  5 sends/hour, 5 attempts) are ours, as for msg91.

#### C2. OTP provider `startmessaging` (the owner's final choice)

Fast2SMS's cheap OTP route needs a website verification its panel no longer offers, and its other
routes need DLT or cost ₹7 per SMS, so the owner chose **StartMessaging** (startmessaging.com):
₹0.25 per SMS, no DLT of our own (their pre-approved templates and shared sender IDs), one-time
KYC on their side. Same model as fast2sms / msg91 — our code, our verification, every app
version works.

- `OTP_PROVIDER=startmessaging` + `STARTMESSAGING_API_KEY` (`sm_live_…`) + optional
  `STARTMESSAGING_TEMPLATE_ID` (their docs call it "required for DLT routes"; left out of the
  request when empty);
  `STARTMESSAGING_APP_NAME` (default `Wedbook`) fills the template's app-name variable.
- Send: `POST https://api.startmessaging.com/otp/send`, header `X-API-Key`, JSON
  `{phoneNumber: '+91<10 digits>', templateId?, variables: {otp: '<code>', appName}}`. Success =
  HTTP 2xx with `success: true`; anything else → logged, `503 otp_provider_error`, nothing stored.
- Test hook `STARTMESSAGING_API_URL` (default the URL above).

#### E. Public website for Razorpay's review (owner request)

Razorpay asks for the link where payments are collected and for test login details. The apps are
not on the Play Store, so the API's domain root serves a small public website (no login,
mobile-friendly, Wedbook Matrimony wine/gold look, logo):

- `/` — what Wedbook Matrimony is, how it works (install → sign in with mobile + OTP → choose your
  agent and register your profile → pay the ₹150 registration fee → your agent approves → browse
  and send interests), the price, **download buttons** for both apps, links to every page below.
- `/about`, `/contact`, `/pricing`, `/terms`, `/privacy`, `/refunds` (refund & cancellation),
  `/shipping` (delivery of a digital service) — the pages Razorpay checks.
- `/download/wedbook-matrimony.apk`, `/download/wedbook-agent.apk` — the current APKs, copied to
  `<UPLOADS_DIR>/downloads/` on the server (`application/vnd.android.package-archive`); a missing
  file → a friendly 404 page.
- Business identity from env: `SITE_BUSINESS_NAME` (default "Wedbook"), `SITE_ADDRESS`,
  `SITE_EMAIL`, `SITE_PHONE`; a missing value is simply left out of the pages.
- **Refund rule (owner's choice):** the ₹150 fee is refunded in full on request until the
  customer's agent approves the profile (it goes live); after that it is not refundable; a
  duplicate payment is always refunded. Refunds go back to the original payment method through
  Razorpay (usually 5–7 working days).

#### F. Reviewer login and demo accounts (owner approved)

- `OTP_REVIEW_PHONE` + `OTP_REVIEW_CODE` (env, both required): for that one number the customer
  login never sends an SMS (whatever `OTP_PROVIDER` is, Firebase included) — the code is
  `OTP_REVIEW_CODE`, stored and checked like any other code (same expiry, attempts and
  throttles), and never echoed. The send response says `provider: 'review'` (the apps treat it as
  the normal code flow). Agent signup for that number is unaffected.
- Production demo data, created once by hand: **Wedbook Demo Agent** (`6000000002`, active, no
  State/code, random password nobody uses) and **Demo Customer** (`6000000001` = the review
  number) linked to it, pending, with one unpaid, hidden profile "Demo Profile" — so the reviewer
  lands on *Pay ₹150*. The demo agent keeps no communities afterwards, so it is not in the
  customers' agent directory and nobody can link to it. Delete both once Razorpay has approved
  the account.

#### D. Fresh start (production, 2026-11-11)

At the owner's request every agent, customer and profile created before agent codes / profile IDs
existed was deleted from production (with their photos, requests, interests, shares, payments,
shortlists and devices); master lists and the agent-code counters were kept. Two admin accounts
remain: `9515702350` and `9036384100` (each picks a State on first login to get an agent code).
Before: 8 agents (none with a code), 22 customers, 20 profiles, 48 photos, 20 payments. Backups
taken just before: `~/backups/db-pre-wipe-20261111-052710.sql.gz` and
`~/backups/uploads-pre-wipe-20261111-052710.tgz` on the VM. No agent code had been issued yet, so
the first codes are `KA1A`, `TS1A`, …

## 8. Explicit v2 (do NOT build now)
iOS build, Telugu/Hindi UI, horoscope matching/compatibility scores, in-app chat, AI import of old WhatsApp chat exports, OTP providers other than mock / msg91 / firebase (§9.19).
