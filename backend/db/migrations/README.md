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
