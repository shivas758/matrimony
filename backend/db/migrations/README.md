# Migrations

`schema.sql` is applied once, on the **first** start of the `db` container.
Any change after that goes in a numbered file here and is applied by hand:

```bash
docker compose exec -T db psql -U matrimony -d matrimony < db/migrations/001_example.sql
```

Naming: `001_add_x.sql`, `002_...`. Keep each file idempotent where you can
(`ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`) so a re-run is safe.
Update `schema.sql` too, so a fresh install and a migrated install match.

Applied so far:

- `001_subcastes.sql` — subcastes master + `profiles.subcaste_id`
- `002_profile_fields_password_reset.sql` — complexions/countries masters, the extra
  profile fields (gothram, work place, details, weight, NRI, parents), and the
  forgot-password tables/flags
- `003_birth_details_hold_requests.sql` — `profiles.birth_time` / `birth_place`, the
  `on_hold` profile status and the `hold_requests` table
- `004_mediator_fields_pdf_share.sql` — religions/languages/food_habits masters,
  `profiles.religion_id` / `mother_tongue_id` / `food_habit_id`, `profile_languages`,
  the siblings columns, and the `pdf` share method
- `005_customers_otp_profile_fields.sql` — Gandharva customers, OTP codes, interests, agent
  change requests, the registration-form profile fields (education levels, occupation type,
  nationality, birth state/country, work country, parents' occupations, siblings counts,
  property), `agents.city` / `registration_token`, and 'India' in `countries`
- `006_guest_mode_payments.sql` — Gandharva guest mode (`customers.status` 'guest', nullable
  `agent_id`), up to 5 profiles per customer, `profiles.paid_at`, the `payments` table and
  `customer_interests.from_profile_id`; existing customer profiles are grandfathered as paid
  on the first run only
- `007_delete_requests_cash.sql` — `profile_delete_requests` (a customer asks to delete a paid
  profile, their agent approves) and cash payments (`payments.provider` 'cash',
  `recorded_by`, `note`)
- `008_push_devices.sql` — `push_devices` (one FCM token per app install, with the cursor
  the push sender uses)
- `009_one_profile_per_customer.sql` — one profile per customer again (SPEC §9.17): the
  partial unique index `uq_profiles_one_per_customer` (skipped with a NOTICE if a customer
  already owns several)
- `010_wedbook_codes_privacy.sql` — Wedbook (SPEC §9.18): the `states` master,
  `agents.state_id` / `agent_code` / `profile_seq`, `agent_code_counters`,
  `profiles.profile_code`, the privacy toggles (`profiles.hidden_fields`) and the community
  audience (`profiles.audience_all` / `audience_community_ids`). Issues no codes itself —
  agents choose their State in the app
- `011_razorpay_settlement.sql` — Razorpay settlement (SPEC §9.19 B): `payments.status`
  gains `refund_due`; unique index `uq_payments_razorpay_order` on the Razorpay order id.
  No data changes
- `012_upi_payments_community_fee.sql` — direct UPI + paid extra communities + account deletion
  (SPEC §9.20): `payments` gains provider `upi`, status `submitted`, purpose `extra_community`,
  `utr` / `submitted_at` / `verified_by` / `verified_at` / `reject_reason` / `agent_id` /
  `community_request_id`; `community_change_requests.fee_paise`; new `account_deletion_requests`.
  No data changes
- `013_demo_world.sql` — store-review demo world (SPEC §9.21): `is_demo` on agents, customers and
  profiles; triggers keep a profile's flag equal to its uploader's. No data changes
- `014_reports_blocks_terms.sql` — report, block, terms consent (SPEC §9.22): `reports`, `blocks`,
  `customers.terms_accepted_at`, `agents.terms_accepted_at`. No data changes
- `015_gift_codes_agent_approval.sql` — gift codes, approved agents, publish last (SPEC §9.23):
  `agents.approved_at` / `approved_by` / `gift_codes_granted_at`, new `gift_codes`, payments
  provider `gift`, `profiles.uploaded_by` nullable (+ `profiles_owner_check`), the demo trigger
  falls back to the customer's flag. Data: first run turns `pending` agents `active`; every run
  approves admins, demo agents and agents with 10 live clients

**Re-runs:** `deploy/update.sh` applies every file on every deploy, in order. A migration must never
*narrow* something a later one widened: 007 and 011 only touch the payments checks while those are
still in their old form (a `DO` block), because re-adding them broke the 2026-11-13 deploy once
`upi` / `submitted` rows existed. 012 does the same since 015 added `gift`.
