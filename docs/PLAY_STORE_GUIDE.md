# Uploading Wedbook Matrimony and Wedbook Agent to Google Play — click-by-click

Do everything below **twice**: once for **Wedbook Matrimony** (the families' app) and once for
**Wedbook Agent** (the agents' app). Where the answers differ, both are given.
Play Console labels change a little from time to time — if a button is named slightly
differently, look for the closest match in the same place.

---

## 0. Before you start — have these ready

| What | Where |
|---|---|
| Wedbook Matrimony app bundle | `wedbook-matrimony-v3.3.0.aab` (project folder) |
| Wedbook Agent app bundle | `wedbook-agent-v3.3.0.aab` (project folder) |
| Texts to copy & paste | `store/wedbook-matrimony/listing.md`, `store/wedbook-agent/listing.md` |
| Icons, banners, screenshots | `store/wedbook-matrimony/` and `store/wedbook-agent/` (`icon-512.png`, `feature-graphic-1024x500.png`, `screenshots/`) |
| Review logins for Google | `store/review-logins.txt` (kept out of GitHub) |
| A support **email address** | Play requires one for each app (Gmail is fine) |
| **12 or more testers** | Their Gmail addresses — agents, family, friends with Android phones |

**Back up the folder `C:\Users\shiva\wedbook-keys`** (two `.jks` files and two `key-*.properties`)
to Google Drive or a USB stick now. These are the **upload keys** — every future update must be
signed with them. If they are ever lost: Play Console → *Test and release → App integrity → App
signing → Request upload key reset*.

**Why 12 testers?** Personal developer accounts created after 13 Nov 2023 must run a **closed
test with at least 12 testers for 14 days** before the app can go public. Organization accounts
(with a D-U-N-S number) skip this. Your Play Console **Dashboard** tells you if it applies.

---

## 1. Create the app

1. Open https://play.google.com/console and sign in.
2. Click **Create app** (top right of *All apps*).
3. Fill in:
   - **App name:** `Wedbook Matrimony` / `Wedbook Agent`
   - **Default language:** *English (India) – en-IN*
   - **App or game:** *App*
   - **Free or paid:** *Free*
   - Tick both **Declarations** (Developer Program Policies, US export laws).
4. Click **Create app**. You land on the app's **Dashboard**, which lists every remaining task.

---

## 2. App content (the policy questions)

Left menu: **Policy and programs → App content** (also reachable from the Dashboard's
*"Set up your app"* list). Do each item and press **Save**:

### 2.1 Privacy policy
- Wedbook Matrimony: `https://matrimony-backend.duckdns.org/privacy/matrimony`
- Wedbook Agent: `https://matrimony-backend.duckdns.org/privacy/agent`
- → **Save**.

### 2.2 App access
- Choose **All or some functionality in my app is restricted** → **Add instructions** and copy
  the username, password and instructions for that app from `store/review-logins.txt`:
  - **Wedbook Matrimony** — Username `6000000001`, Password: see the file (the fixed OTP,
    `OTP_REVIEW_CODE`; no SMS is sent to this test number). The account is approved and paid, so the reviewer can browse, open profiles
    and send interests.
  - **Wedbook Agent** — Username `6000000002`, Password: see the file. The demo agent has 8 demo
    profiles and one demo client.
  - Both live in a separate **demo world**: they see only demo profiles (placeholder photos), and
    your real users never see the demo profiles.
- **Save**.

### 2.3 Ads
- **No, my app does not contain ads** → **Save**.

### 2.4 Content rating

**Wedbook Matrimony** — category **Social or Communication** → **Social**, then:

| Question | Answer |
|---|---|
| Significant portion used to connect people for dating or sexual relationships? | **Yes** (matrimony) |
| Public sharing of nudity? | No |
| Public sharing of real-world graphic violence? | No |
| Shares the user's current and precise location? | No |
| Users can purchase digital goods? | No (until Google Play Billing is added — then Yes) |
| Ability to block users or user-generated content? | **Yes** (⋮ → Block, from version 3.3.0) |
| Ability to report users or user-generated content? | **Yes** (⋮ → Report profile, from version 3.3.0) |
| Chat moderation? | No (there is no chat) |
| Interactions limited to invited friends only? | No |

**Wedbook Agent** — use the steps below (category *All Other App Types*).

#### General steps
1. **Start questionnaire** → enter your email → category:
   - Wedbook Matrimony: **Social Networking, Forums, Blogs and User-Generated Content Sharing**
   - Wedbook Agent: **All Other App Types** (Utility / Productivity / Communication / Other)
2. Answer honestly. For these apps: violence **No**, sexual content **No**, bad language **No**,
   drugs/alcohol/tobacco **No**, gambling **No**.
   - "Users can interact or exchange content?" → **Yes** for Wedbook Matrimony (interests,
     profile photos and details are seen by other members); for Wedbook Agent **Yes** (agents
     share profiles and requests).
   - "Shares the user's current physical location?" → **No**.
   - "Allows users to purchase digital goods?" → **No** for this first version (there is no
     in-app payment in the Play version yet — change this when Google Play Billing is added).
3. **Save** → **Next** → **Submit**. A rating is shown immediately.

### 2.5 Target audience and content
- Target age groups: tick **18 and over** only → **Next**.
- "Could your app unintentionally appeal to children?" → **No** → **Save**.

### 2.6 News app
- **No** → **Save**.

### 2.7 Data safety
Click **Start**, then:

1. **Data collection and security**
   - Does your app collect or share any of the required user data types? → **Yes**
   - Is all of the user data collected by your app encrypted in transit? → **Yes**
   - Account creation: Wedbook Matrimony → **Username and other authentication** (mobile number
     + OTP). Wedbook Agent → **Username and password** (mobile number + password).
   - Delete account URL:
     `https://matrimony-backend.duckdns.org/delete-account/matrimony` (Matrimony) or
     `https://matrimony-backend.duckdns.org/delete-account/agent` (Agent).
   - Can users ask to delete some data without deleting their account? → **Yes** (Matrimony:
     an unpaid profile can be deleted in the app) / **No** (Agent).
2. **Data types** — tick these (for every one: *Collected* = yes, *Shared* = **no**, *Processed
   ephemerally* = **no**, *Purposes* = **App functionality** and **Account management**):

   | Section | Data type | Matrimony | Agent | Required? |
   |---|---|---|---|---|
   | Personal info | Name | ✓ | ✓ | Required |
   | Personal info | Phone number | ✓ | ✓ | Required |
   | Personal info | Address (city, native place, work place) | ✓ | ✓ | Optional |
   | Personal info | Race and ethnicity (community, sub-caste) | ✓ | ✓ | Optional |
   | Personal info | Political or religious beliefs (religion) | ✓ | ✓ | Optional |
   | Personal info | Other info (date of birth, height, horoscope, family, education) | ✓ | ✓ | Optional |
   | Financial info | Purchase history (registration / community fee status) | ✓ | ✓ | Optional |
   | Financial info | Other financial info (income on a profile) | ✓ | ✓ | Optional |
   | Photos and videos | Photos | ✓ | ✓ | Optional |
   | App activity | App interactions (interests, requests) | ✓ | ✓ | Optional |
   | Device or other IDs | Device or other IDs (notification token) | ✓ | ✓ | Optional |

   For **Wedbook Agent**, the profile data is entered by the agent on behalf of families — still
   tick it; it is collected through the app.
3. **Next** → review the preview → **Save**.

### 2.8 Government apps
- **No** → **Save**.

### 2.9 Financial features
- **My app doesn't provide any financial features** → **Save**.

### 2.10 Health
- **My app does not have any health features** → **Save**.

### 2.11 Advertising ID
- "Does your app use advertising ID?" → **No** → **Save**.

---

## 3. Store settings

Left menu: **Grow users → Store presence → Store settings**:
- **App category:** Wedbook Matrimony → *Lifestyle*; Wedbook Agent → *Business*.
- **Tags:** pick from the lists in `listing.md`.
- **Store listing contact details:** email (required), phone `+91 9036384100`, website
  `https://matrimony-backend.duckdns.org/`.
- **Save**.

---

## 4. Main store listing

Left menu: **Grow users → Store presence → Main store listing**:
1. **App name**, **Short description**, **Full description** — copy from the app's `listing.md`.
2. **Graphics:**
   - **App icon** → upload `icon-512.png`.
   - **Feature graphic** → upload `feature-graphic-1024x500.png`.
   - **Phone screenshots** → upload every file in `screenshots/` in number order (you can drag
     to reorder).
   - Tablet / Chromebook screenshots: leave empty.
3. **Save**.

---

## 5. First release: closed test

Left menu: **Test and release → Testing → Closed testing**.

1. Click **Create track** (or open the existing *Closed testing – Alpha* track) → name it
   `Testers`.
2. **Countries / regions** tab → **Add countries / regions** → tick **India** → **Add** →
   **Save**.
3. **Testers** tab → **Create email list** → List name `Wedbook testers` → add the 12+ Gmail
   addresses (comma-separated or one per line) → **Save changes** → tick the list → **Save**.
   - Feedback URL or email: your support email.
4. **Releases** tab → **Create new release**.
   - **App integrity / Play App Signing:** if asked, choose **Use Google-generated key**
     (recommended). Your file is signed with the *upload key*; Google re-signs it for users.
   - **App bundles** → **Upload** → choose `wedbook-matrimony-v3.3.0.aab` (or
     `wedbook-agent-v3.3.0.aab`). Wait for the upload to finish.
   - **Release name:** filled in automatically (e.g. `9 (3.2.0)`) — keep it.
   - **Release notes:** paste the text from `listing.md` between `<en-IN>` and `</en-IN>`.
   - Click **Next**. Errors (red) must be fixed; warnings (yellow) can usually be ignored.
   - Click **Save and publish** (or **Save** → **Go to overview** → **Send changes for
     review**).
5. Left menu **Publishing overview** shows the review. The first review takes from a few hours to
   a few days. You get an email when it's done.
6. When approved: **Closed testing → Testers** tab → **Copy link**. Send that link to your
   testers on WhatsApp. Each tester must:
   - open the link **on their Android phone, signed in with the Gmail you added**,
   - tap **Become a tester**, then **Download it on Google Play** and install,
   - **if they have the WhatsApp version installed: uninstall it first** (the Play version is
     signed with a different key, so it cannot install over it — their account is safe on the
     server, they simply log in again),
   - keep the app installed and stay opted in for **14 days**.

---

## 6. Apply for production (after 14 days)

1. **Dashboard** → the card **Apply for production** becomes active once 12+ testers have been
   opted in for 14 days.
2. Answer the questions (how you found testers, what feedback you got, what you changed) — short
   honest answers are fine.
3. **Submit**. Google replies within about 7 days.

**Before this step, Google Play Billing must be added** to both apps (the Play version has no
online payment today because Play allows only Google's billing for in-app features). Tell me when
your **Payments profile** is set up (*Setup → Payments profile*) and I'll add it.

---

## 7. Production release

1. **Test and release → Production** → **Countries / regions** → add **India** → **Save**.
2. **Create new release** → **Add from library** → pick the tested bundle (or upload a newer one I
   build) → release notes → **Next** → **Save and publish**.
3. Optional: choose a **staged rollout** (e.g. 20%) and increase it later.

---

## 8. Later updates

- I build a new `.aab` with a higher version number for every update — upload it with **Create
  new release** on the same track (testing or production).
- Always keep the WhatsApp APK and the Play version apart: someone who moves from one to the
  other uninstalls once.

## 9. If something goes wrong

| Message in Play Console | What to do |
|---|---|
| "You uploaded an APK or Android App Bundle that was signed in debug mode" | You picked an `.apk` — upload the `.aab` file instead. |
| "Version code 9 has already been used" | Ask me for a new build; every upload needs a new version number. |
| "Your app targets API level …" | Ask me to rebuild — the apps target API 36 today, which Play requires. |
| Rejected for "App access" | Check the review logins still work (`store/review-logins.txt`) and resubmit. |
| Rejected for "Account deletion" | The link `…/delete-account` must open in a browser — check it, then resubmit. |
