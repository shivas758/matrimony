# Matrimony Agents — Flutter app (Android)

Screens follow `../docs/SPEC.md` §5. Business rules live in `../CLAUDE.md`.

## Point the app at a backend

`lib/config.dart` is the **only** place the API location lives. It reads a
build-time constant so the same code ships to dev and production:

| Where you run it | `API_BASE_URL` |
|---|---|
| Android emulator → backend on this PC | `http://10.0.2.2:3000` (default) |
| Real phone → backend on your LAN | `http://192.168.x.x:3000` (see note below) |
| Production | `https://your-domain.example.in` |

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

> Plain HTTP is blocked except for `10.0.2.2` / `localhost`
> (`android/app/src/main/res/xml/network_security_config.xml`). To test against a
> LAN IP, add it there temporarily, and remove it before sharing the APK.

## Build the APK for agents

```bash
flutter build apk --release --target-platform android-arm,android-arm64 --dart-define=API_BASE_URL=https://your-domain.example.in
```

The file lands at `build/app/outputs/flutter-apk/app-release.apk` (~34 MB) — send that
over WhatsApp. Agents must enable "Install unknown apps" once.

`--target-platform android-arm,android-arm64` drops the x86 slices that only emulators
use; without it the APK is ~53 MB. Every real Android phone is covered by the two ARM
architectures.

> The release build is currently signed with the debug key (Flutter's default).
> That is fine for direct WhatsApp distribution. Add a real keystore in
> `android/app/build.gradle.kts` before any Play Store upload.

## Checks

```bash
flutter analyze
flutter test
```

## Layout

```
lib/
  config.dart            API base URL and app-wide constants
  main.dart              providers, theme, splash → login → pending → home
  models/                agent, profile, master_data, contact_request, shortlist, notifications
  services/              api_client (Dio + JWT), auth, profile, contact, share, admin
  state/                 auth_state, masters_state, profiles_state, profile_filters
  ui/
    theme.dart           Material 3, large touch targets
    strings.dart         every user-facing string (ready for Telugu/Hindi later)
    widgets/common.dart  photo, status chip, detail row, empty/error states
    screens/
      auth/              login, signup (community chips), pending approval
      profiles/          list + filter sheet (age slider), detail, add/edit, my uploads
      requests/          received / sent contact requests
      shortlists/        grouped by client label
      admin/             dashboard, agents, community requests, master lists, logs
      more_screen.dart   profile, navigation, logout
      settings_screen.dart  my communities, request another, change password
```

## How the rules show up in the UI

- **Community visibility** — the list only ever renders what the API returns; the
  add/edit form limits the community dropdown to the agent's own communities.
- **Pending agents** — `PendingScreen` is the only screen they can reach; pull to
  refresh re-checks `/auth/me`.
- **Contact protection** — `Profile.contactPhone` is null unless the server sent it.
  The detail screen shows Request / Pending / phone + days-left based on
  `contact_access`, and never assumes the field exists.
- **Masked sharing** — the app never builds share text itself; it uses the
  `whatsapp_text` and card image the server produces.
- **Uploader anonymity** — the Sent tab has no `requester` field to show, and
  profile detail only exposes `uploaded_by` to the uploader or an admin.
