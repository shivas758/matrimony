# Oracle Cloud Free Tier — Server Setup

Copy-paste guide, start to finish. Budget about an hour, most of it waiting.
Sections 0–3 set up the account, the server and the domain; 4–10 install and ship the app.

**You need:** an Oracle Cloud account (section 1 — skip it if you already have one) and
the backend running locally once (`docker compose up -d --build`).

Throughout, replace these two placeholders with your real values:

| Placeholder | What to type | Example |
|---|---|---|
| `YOUR_PUBLIC_IP` | The **numeric** public IP of the VM, from the Oracle instance page | `152.67.12.34` |
| `your-domain.example.com` | Your DuckDNS or registrar hostname | `shiva-matrimony.duckdns.org` |

**`ssh`/`scp` always use the numeric IP**, never the domain — you connect to the server
before DNS is set up, and the IP keeps working even if DNS breaks later.
The domain is only used for `PUBLIC_BASE_URL`, the Caddyfile, and the app's `API_BASE_URL`.
Every `ssh`/`scp` assumes the key from section 0; add `-i ~/.ssh/matrimony_oracle` if you
have not put it in your SSH agent.

---

## Using a different VPS provider

Oracle's Always Free ARM capacity is frequently exhausted, so this may end up running on
an ordinary paid VPS (Hostinger, OVH, WebEyeSoft, Vultr, DigitalOcean…). Almost nothing
changes. The deltas:

| Section | Change |
|---|---|
| 1, 2 | **Skip.** Buy the VPS instead. Minimum useful spec: **2 GB RAM, 30 GB disk, 1 TB bandwidth, KVM virtualisation, Ubuntu 24.04, a dedicated IPv4.** |
| 2 → security list | **Skip.** No Oracle console. Use the provider's firewall panel, or `ufw` on the VM, to allow 22, 80 and 443. |
| 3 | Unchanged — DuckDNS A record → the VPS IP. |
| 4 | On **x86** providers change the Docker apt line from `arch=arm64` to **`arch=amd64`**. Skip the `iptables` block unless the provider ships restrictive rules. |
| 5–12 | Unchanged. |

`bcrypt` and `sharp` both publish `linux-x64-musl` prebuilds, so the Docker image builds
on x86 exactly as it does on ARM — nothing compiles either way.

If the provider gives you a **root password** instead of taking your public key, install
the key on first login so the rest of the guide works non-interactively:

```bash
ssh root@YOUR_PUBLIC_IP           # using the emailed password
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'PASTE_YOUR_matrimony_oracle.pub_LINE_HERE' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

The guide assumes a sudo-capable `ubuntu` user. If your provider gives you `root`
instead, either drop the `sudo ` prefixes, or create the user once:

```bash
adduser --disabled-password --gecos "" ubuntu
usermod -aG sudo ubuntu
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu
rsync --archive --chown=ubuntu:ubuntu ~/.ssh /home/ubuntu
```

Choose the plain **Ubuntu 24.04** OS image, not a provider "Docker" one-click — those
usually install Ubuntu's older `docker.io` without the Compose plugin that section 4
expects.

---

## 0. Make an SSH key first

**Already have `~/.ssh/matrimony_oracle`? Skip to section 2.** Check with:

```bash
ssh-keygen -l -f ~/.ssh/matrimony_oracle.pub     # prints the fingerprint if it exists
```

Do this before touching the Oracle console — you paste the **public** half into the
instance form, and it cannot be added as easily afterwards.

On your PC, **in Git Bash** (not PowerShell — see the warning below):

```bash
ssh-keygen -t ed25519 -C "matrimony" -f ~/.ssh/matrimony_oracle
```

Press Enter twice to leave the passphrase empty (a passphrase means every deploy command
stops to ask for it). Then print the public key — this is the text you paste into Oracle:

```bash
cat ~/.ssh/matrimony_oracle.pub
```

Never share `~/.ssh/matrimony_oracle` (no `.pub`) — that is the private half.

> **Windows: run this in Git Bash, not PowerShell.** Windows' `ssh-keygen` does not
> expand `~`, so in PowerShell it tries to create a folder literally named `~` and fails
> with `Saving key "~/.ssh/matrimony_oracle" failed: No such file or directory`.
> In PowerShell use the full path instead:
>
> ```powershell
> ssh-keygen -t ed25519 -C "matrimony" -f "$env:USERPROFILE\.ssh\matrimony_oracle"
> ```
>
> Both shells share the same `C:\Users\<you>\.ssh`, so either is fine once the path is real.

> **Windows: lock the key down**, or OpenSSH refuses it with
> *"Permissions for … are too open"*:
>
> ```powershell
> icacls "$env:USERPROFILE\.ssh\matrimony_oracle" /inheritance:r /grant:r "$($env:USERNAME):(R,W)"
> ```

## 1. Create the Oracle account

**Already have an Oracle account? Skip to section 2.**

1. Go to <https://cloud.oracle.com> → **Start for free**.
2. Enter email, country **India**, and verify by email and SMS.
3. **Home Region — this cannot be changed later.** Choose the one nearest you:
   *India South (Hyderabad)* or *India West (Mumbai)*. All your free resources are
   locked to this region forever.
4. Oracle asks for a **credit/debit card** to verify identity. Always Free stays ₹0;
   expect a temporary hold of roughly ₹100 that is released. Your account stays on
   "Always Free" until *you* explicitly upgrade.
5. Accept the agreement and finish. Provisioning your tenancy takes a few minutes.

## 2. Create the VM

Console → hamburger menu ☰ → **Compute → Instances → Create instance**

| Field | Value |
|---|---|
| Name | `matrimony-api` |
| Placement | leave the default Availability Domain |
| **Image** | Edit → Change image → **Canonical Ubuntu** → **24.04** |
| **Shape** | Edit → Change shape → **Ampere** → `VM.Standard.A1.Flex` → **2 OCPUs, 12 GB** |
| Networking | Create new VCN (defaults are fine) · **Assign public IPv4 address: Yes** |
| **SSH keys** | *Paste public keys* → paste the `ssh-ed25519 …` line from step 0 |
| Boot volume | Tick *Specify a custom boot volume size* → **100 GB** |

Click **Create**. When the state turns green *Running*, copy the **Public IP address** —
that numeric address is the `YOUR_PUBLIC_IP` used by every `ssh` and `scp` below.

> **This one VM uses your entire free ARM allowance.** Always Free gives 2 OCPUs and
> 12 GB of Ampere capacity in total, not per instance — so check
> **Compute → Instances** first and delete or shrink any existing A1 instance, or the
> create will fail on quota. Block storage is 200 GB total, so a 100 GB boot volume
> leaves room for one more.
>
> 2 OCPU / 12 GB is comfortable here: Postgres, the API and Caddy together idle at well
> under 1 GB, and the load is 10–50 agents.

> ### "Out of capacity for shape VM.Standard.A1.Flex"
>
> Expect this — free ARM capacity in Indian regions is usually exhausted. Nothing is
> wrong with your configuration. Hit **Previous**, change one thing, and **Create**
> again. In order of what actually works:
>
> 1. **Shrink the shape to 1 OCPU / 6 GB.** Much easier to place than 2/12, and still
>    far more than this app needs — Postgres, the API and Caddy idle under 1 GB combined.
>    Try this first; it costs nothing and often succeeds immediately. You can resize
>    upward later once capacity frees up.
> 2. **Try another Availability Domain** — but check the *Placement* dropdown first.
>    Most Indian regions have only AD-1, in which case this option does not exist.
> 3. **Retry at a different time of day.** Capacity is released constantly as others
>    delete instances. Early morning IST tends to be better. This is a genuine lottery —
>    people often need several attempts over a day or two.
> 4. **Upgrade to Pay As You Go.** The reliable fix: PAYG tenancies get priority for A1
>    capacity, and you still pay ₹0 as long as you stay inside Always Free limits
>    (2 OCPU / 12 GB ARM, 200 GB storage). Billing → Upgrade and Manage Payment.
> 5. **Last resort — AMD `VM.Standard.E2.1.Micro`.** Always Free and far easier to get,
>    but 1 OCPU / 1 GB RAM is genuinely tight: the Docker build can run out of memory.
>    Add swap first (`sudo fallocate -l 2G /swapfile && sudo mkswap /swapfile &&
>    sudo swapon /swapfile`). It is also x86, so use `arch=amd64` in the Docker apt line
>    in section 4.
>
> ### "Shape … is not valid for image ocid1.image…"
>
> You switched between an ARM and an x86 shape without re-picking the image. Ubuntu
> ships separate `aarch64` and `x86_64` builds and they are not interchangeable:
>
> | Shape | Architecture | Image build you must select |
> |---|---|---|
> | `VM.Standard.A1.Flex` | ARM64 | Canonical Ubuntu 24.04 **aarch64** |
> | `VM.Standard.E2.1.Micro` | x86 | Canonical Ubuntu 24.04 **x86_64** |
>
> Fix: **change the shape first, then re-open Edit → Change image and select Ubuntu
> 24.04 again.** Oracle filters the image list to the current shape, so re-selecting
> picks up the right architecture. Changing the image first and the shape second leaves
> the old, incompatible image OCID attached — which is exactly this error.

Verify you can get in before going further — use the **numeric IP**, not a domain
(you have not set DNS up yet at this point):

```bash
ssh -i ~/.ssh/matrimony_oracle ubuntu@152.67.12.34     # your VM's real IP
```

Type `yes` at the host-key prompt. If it hangs instead of asking, the security list
(next section) or the key is wrong.

### Open ports 80 and 443

Console → ☰ → **Networking → Virtual cloud networks** → your VCN → **Subnets** → the
subnet → **Security Lists** → *Default Security List* → **Add Ingress Rules**.

Add two rules, both with:

| Field | Value |
|---|---|
| Stateless | No |
| Source Type | CIDR |
| Source CIDR | `0.0.0.0/0` |
| IP Protocol | TCP |
| Destination Port Range | `80` for the first rule, `443` for the second |

| Port | Why |
|---|---|
| 80 | Let's Encrypt certificate challenge |
| 443 | The app itself |

Do **not** open 3000. The API is bound to loopback and is only reachable through Caddy.

## 3. Get a domain and point it at the VM — do this now

DNS takes time to propagate, so set it before installing anything.

### Option A — DuckDNS (free, 2 minutes) — recommended to start

1. Go to <https://www.duckdns.org> and sign in with Google/GitHub (no password to create).
2. Type a subdomain, e.g. `shiva-matrimony`, and click **add domain**.
   You now own `shiva-matrimony.duckdns.org`.
3. Put your VM's **public IP** in the *current ip* box and click **update ip**.

That is the whole thing. Free forever, no renewal.

### Option B — your own domain (~₹700/year, looks professional to agents)

Buy from Cloudflare, Namecheap, BigRock or GoDaddy, then in its DNS panel add:

| Type | Name | Value | TTL |
|---|---|---|---|
| A | `profiles` | `YOUR_PUBLIC_IP` | 300 (5 min) |

giving you `profiles.yourdomain.in`. Using a subdomain leaves the bare domain free for a
website later. On Cloudflare, set the proxy toggle to **DNS only** (grey cloud) — the
orange-cloud proxy interferes with Caddy getting its certificate.

### Verify before continuing

```bash
nslookup your-domain.example.com
```

It must print your VM's public IP. DuckDNS is near-instant; a registrar can take
5–30 minutes. **Do not start section 5 until this resolves** — Caddy cannot obtain a
certificate for a name that does not point at the VM yet.

## 4. Install Docker on the VM

```bash
ssh -i ~/.ssh/matrimony_oracle ubuntu@YOUR_PUBLIC_IP
```

```bash
sudo apt-get update && sudo apt-get install -y ca-certificates curl git rsync
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker ubuntu && newgrp docker
```

Oracle's Ubuntu images ship with restrictive iptables rules, so open the ports there too:

```bash
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo apt-get install -y iptables-persistent && sudo netfilter-persistent save
```

Check Docker works: `docker run --rm hello-world`

## 5. Install Caddy (HTTPS)

Install it before the app — Caddy gets its certificate on its own and will simply
return 502 until the API is up.

```bash
sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update && sudo apt-get install -y caddy
```

```bash
sudo tee /etc/caddy/Caddyfile >/dev/null <<'EOF'
your-domain.example.com {
    # Profile photos are up to 10 MB each, 8 per upload.
    request_body {
        max_size 100MB
    }
    reverse_proxy localhost:3000
}
EOF
sudo systemctl restart caddy
```

Edit the domain in that file first (`sudo nano /etc/caddy/Caddyfile`), then:

```bash
curl -I https://your-domain.example.com     # expect 502 for now — that means TLS works
sudo journalctl -u caddy -n 20 --no-pager   # confirms the certificate was obtained
```

If you see a certificate error, DNS has not propagated yet. Wait and restart Caddy.

## 6. Ship the backend

**On your PC**, from the project root:

```bash
./deploy/package.sh
scp -i ~/.ssh/matrimony_oracle matrimony-backend.tgz ubuntu@YOUR_PUBLIC_IP:~/
```

This packs only what the server needs (~70 KB). It deliberately leaves out
`node_modules`, `uploads/`, the Flutter app, and **every `.env` file** — your local
development secrets must never reach the server.

**On the VM:**

```bash
mkdir -p ~/matrimony-agents && tar xzf ~/matrimony-backend.tgz -C ~/matrimony-agents
cd ~/matrimony-agents/backend
```

Generate a fresh `.env` — note `PUBLIC_BASE_URL` uses your **https** domain, because
it is what public share links are built from:

```bash
cat > .env <<EOF
DB_NAME=matrimony
DB_USER=matrimony
DB_PASSWORD=$(openssl rand -hex 24)
JWT_SECRET=$(openssl rand -hex 32)
PUBLIC_BASE_URL=https://your-domain.example.com
EOF
nano .env      # fix PUBLIC_BASE_URL to your real domain
chmod 600 .env
```

> Getting `PUBLIC_BASE_URL` wrong is the most common mistake here. If it says
> `localhost`, every share link an agent sends will be dead on the recipient's phone.

Build and start:

```bash
docker compose up -d --build      # first build takes ~5 min on the free-tier ARM VM
docker compose ps                 # both services should be "running"/"healthy"
curl http://localhost:3000/api/health          # {"ok":true}
curl https://your-domain.example.com/api/health # {"ok":true}  ← through Caddy
```

`db/schema.sql` runs automatically the **first** time the `db` container starts, creating
every table plus the seed data and the default admin.

Nothing compiles during the build: `bcrypt` and `sharp` both ship prebuilt
`linux-arm64-musl` binaries, and the image installs `font-dejavu` so `sharp` can
rasterise the watermark and share-card text. This was verified by building the image
for `linux/arm64` and loading both modules — see "What has been tested" at the bottom.

## 7. Verify the deployment

Run the full suite from **your PC**, against the live server:

```bash
cd backend && BASE=https://your-domain.example.com npm run smoke
```

All 248 checks must pass. This proves HTTPS, the database, photo upload, watermarking,
the masked public pages, and every permission rule are working on the real server.

> **The smoke test writes data** — it creates test agents, a profile, shares and a
> throwaway community. Run it *before* you add anything real, then wipe the database
> so agents start with a clean system:
>
> ```bash
> docker compose down -v && docker compose up -d      # on the VM; deletes ALL data
> ```
>
> Re-run `curl https://your-domain.example.com/api/health` afterwards to confirm it came back.

## 8. Lock down the admin account

This matters more than anything else on this page. The default admin ships with a
published password.

1. Build and install the APK (step 10), or use curl:

```bash
# log in, then change the password
curl -s -X POST https://your-domain.example.com/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"phone":"9999999999","password":"ChangeMe@123"}'
# copy the "token" from the response into the next command
curl -s -X POST https://your-domain.example.com/api/auth/change-password \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer PASTE_TOKEN_HERE' \
  -d '{"current_password":"ChangeMe@123","new_password":"your-new-strong-password"}'
```

2. In the app: **More → Admin → Master lists → Community** — replace the placeholder
   `Community A/B/C` with your real communities (edit them, or add new ones and switch
   the placeholders off).

## 9. Backups — do not skip

```bash
cp ~/matrimony-agents/deploy/backup.sh ~/backup.sh
chmod +x ~/backup.sh
~/backup.sh                       # run once now to check it works
ls -la ~/backups                  # a db-*.sql.gz and an uploads-*.tgz
```

Schedule it nightly at 02:30:

```bash
crontab -e
```

```
30 2 * * * /home/ubuntu/backup.sh >> /home/ubuntu/backup.log 2>&1
```

What it does, and why:

- **Database** — a gzipped `pg_dump` per night, 14 days kept. These are small (KBs to
  a few MB), so history is cheap.
- **Photos** — an incremental `rsync` mirror at `~/backups/uploads-mirror/`, not a daily
  tarball. A full-size tarball of ~8 GB of photos kept for 14 days would need ~112 GB,
  more than the entire boot volume. The mirror costs one copy, and because it never
  deletes, a photo removed in the app is still recoverable from it.
- **Disk guard** — refuses to run if less than 5 GB is free, so a backup can never be
  the thing that fills the volume.
- Failures are reported into `~/backup.log` rather than failing silently.

**A backup on the same VM is not a backup.** Copy them off:

```bash
sudo apt-get install -y rclone
rclone config          # add an Oracle Object Storage (S3-compatible) remote, also free tier
# then append to the cron line:  && rclone copy ~/backups remote:matrimony-backups
```

### Restoring

```bash
cd ~/matrimony-agents/backend
gunzip -c ~/backups/db-YYYY-MM-DD.sql.gz | docker compose exec -T db psql -U matrimony -d matrimony
sudo rsync -a ~/backups/uploads-mirror/ ~/matrimony-agents/backend/uploads/
docker compose restart api
```

## 10. Build the APKs — Wedbook Agent for agents, Wedbook Matrimony for customers

**On your PC**, pointed at the live domain:

```bash
cd app            # Wedbook Agent (agents)
flutter build apk --release --target-platform android-arm,android-arm64 \
  --dart-define=API_BASE_URL=https://your-domain.example.com

cd ../customer_app   # Wedbook Matrimony (customers)
flutter build apk --release --target-platform android-arm,android-arm64 \
  --dart-define=API_BASE_URL=https://your-domain.example.com
```

Send `app/build/app/outputs/flutter-apk/app-release.apk` (~34 MB) to agents over WhatsApp.
Agents tap it, allow "Install unknown apps" once, and sign up (mobile number + OTP, then
details). You approve them under **More → Admin → Pending agents**.

Agents send `customer_app/build/app/outputs/flutter-apk/app-release.apk` to their customers,
or share their registration-form link from **Clients → Registration form**. A customer who
installs Wedbook Matrimony signs up with their number (OTP) and then chooses their agent by the
agent's mobile number or **agent code** (e.g. `KA1A` — every agent sees their own code in the app
under Settings); the agent approves them under **Clients**.

The domain is compiled into both APKs, so if you ever change the domain you must rebuild
and redistribute both.

## 11. Day-to-day operations

```bash
cd ~/matrimony-agents/backend
docker compose logs -f api        # follow the API log
docker compose ps                 # service health
docker compose restart api        # restart just the API
df -h                             # disk (photos grow over time)
```

**Deploying an update:** re-run `./deploy/package.sh` and `scp` on your PC, then on the VM:

```bash
cd ~/matrimony-agents && tar xzf ~/matrimony-backend.tgz
cd backend
# apply any new migrations first (all are idempotent — re-running is harmless)
for f in db/migrations/*.sql; do docker compose exec -T db psql -U matrimony -d matrimony -v ON_ERROR_STOP=1 < "$f"; done
docker compose up -d --build
curl http://localhost:3000/api/health
```

Your `.env`, database volume, and `uploads/` are untouched — the tarball contains none of them.
The API is down for the few minutes the image rebuilds (longer on a 1 GB Micro).

`deploy/update.sh` runs that whole sequence from your PC in one go, including a pre-update
database dump: `VM_HOST=ubuntu@YOUR_PUBLIC_IP ./deploy/update.sh`.

**Schema changes** go in `backend/db/migrations/` as numbered, idempotent files and are applied
by the loop above. `001_subcastes.sql` is the first; `011_razorpay_settlement.sql` is the latest: it
lets a payment be marked `refund_due` and keeps one row per Razorpay order (v2.9, no data
changes). `010_wedbook_codes_privacy.sql` added the
`states` list, agent codes, customer / profile IDs, the privacy toggles and the community audience
(Wedbook, v2.8). It only adds tables and columns — no codes are issued by the migration: each agent
registered earlier is asked once, on opening Wedbook Agent 3.0.0, to choose their State; that gives them
their code and gives every profile they uploaded its ID. Agents still on an older app build keep working
without a code until they update. `009_one_profile_per_customer.sql` made it one profile per
customer (a unique index, skipped with a NOTICE if a customer already owns several).
`008_push_devices.sql` added push notification devices. `007_delete_requests_cash.sql` added delete requests for paid customer profiles and cash
payments recorded by agents. `006_guest_mode_payments.sql`
added guest mode in the customer app (then called Gandharva, now Wedbook Matrimony), the ₹150 registration fee and up to 5 profiles per customer (one since 009). 006 grandfathers the
customer profiles that exist when it first runs as paid; re-running it later changes nothing.

**OTP for signups and customer logins** — the backend ships with `OTP_PROVIDER=mock`: no SMS is
sent, the code is always `123456` and both apps show it as a hint. That is fine for testing with
your own agents but means **anyone can log in as any customer number**, so switch to real codes
before opening Wedbook Matrimony to the public. Real options: **StartMessaging** (below — the one
chosen), Fast2SMS, Firebase phone auth (both further below, kept as alternatives) or MSG91
(`OTP_PROVIDER=msg91  MSG91_AUTH_KEY=...  MSG91_TEMPLATE_ID=...  MSG91_SENDER=...`, needs a
DLT-registered template).

#### StartMessaging (SPEC §9.19 C2) — the one in use

₹0.25 per SMS, no DLT registration of your own (StartMessaging sends through its pre-approved OTP
templates and shared sender IDs). The server makes the 6-digit code and checks it, so it works
with **every** app version — no APK update needed.

1. Sign up at https://startmessaging.com, finish their one-time **KYC** and top up the wallet.
2. In the dashboard: create / copy the **API key** (starts `sm_live_`, shown only once) and the
   **Template ID** of the OTP template you will use.
3. On the VM:

```bash
cd ~/matrimony-agents/backend
nano .env     # set / add:
              # OTP_PROVIDER=startmessaging
              # STARTMESSAGING_API_KEY=sm_live_...
              # STARTMESSAGING_TEMPLATE_ID=<template id>
              # STARTMESSAGING_APP_NAME=Wedbook       (optional — the app name in the SMS)
docker compose up -d
docker compose logs api | grep "OTP provider"     # should say: OTP provider startmessaging
```

4. Try it in Wedbook Matrimony with your own number. If the app says "Could not send the SMS",
   `docker compose logs api | grep startmessaging` shows StartMessaging's reason. To go back to
   test codes: `OTP_PROVIDER=mock`, `docker compose up -d`.

#### Fast2SMS (SPEC §9.19 C — alternative; its cheap route needs a website verification)

The server sends a 6-digit code through Fast2SMS's ready-made OTP route (the SMS reads like
"Your OTP: 482913"); no DLT registration of your own is needed. Works with **every** app version
already installed — no APK update needed for this.

1. Sign up at https://www.fast2sms.com. In the panel open the **OTP Message** menu and complete
   **website verification** with `https://YOUR_DOMAIN/` (the public site of SPEC §9.19 E). Until
   Fast2SMS approves it, every send fails with error 996 "Before using OTP Message API, complete
   website verification" (seen on 2026-11-11). Complete KYC too if the panel asks.
2. Recharge the wallet with at least **₹100** in one go (the API refuses until the first ₹100
   recharge — error 999). Each OTP SMS is charged from this wallet at your plan's rate.
3. *Dev API* (left menu) → copy the **API key**.
4. On the VM:

```bash
cd ~/matrimony-agents/backend
nano .env     # set / add:
              # OTP_PROVIDER=fast2sms
              # FAST2SMS_API_KEY=<your API key>
docker compose up -d
docker compose logs api | grep "OTP provider"     # should say: OTP provider fast2sms
```

5. Try it: Wedbook Matrimony → enter your number → the SMS arrives within seconds. If the app
   says "Could not send the SMS", see why with
   `docker compose logs api | grep fast2sms` — the line shows Fast2SMS's reason (wrong key, no
   balance, KYC pending, …). To go back to test codes: `OTP_PROVIDER=mock`, `docker compose up -d`.

#### Firebase phone OTP (SPEC §9.19 A — alternative, not in use)

Needs **Wedbook Agent 3.1.0 and Wedbook Matrimony 3.1.0** (older apps answer "Please update the
app to get your code"), so send the new APKs to everyone *before* step 7.

**Cost:** Firebase only sends phone-auth SMS on the pay-as-you-go **Blaze** plan. Roughly the
first 10 SMS a day are free; after that each SMS to India costs about US$0.07 (≈ ₹6) — check
the current rate at https://cloud.google.com/identity-platform/pricing. A customer logs in once
per phone (the login lasts 30 days), so a small bureau network stays near the free part.

1. https://console.firebase.google.com → *Add project* (or open the one you use for push — one
   project serves both). Google Analytics is not needed.
2. *Upgrade* (bottom-left) → **Blaze** → add a card. Then in Google Cloud Console → *Billing →
   Budgets & alerts* set a monthly budget (e.g. ₹500) so you get an email if usage jumps.
3. *Project settings → General → Your apps → Add app → Android*, package name
   `com.matrimonyagents.matrimony_agents` (Wedbook Agent). Skip the google-services.json and SDK
   steps. Repeat for `com.matrimonyagents.gandharva` (Wedbook Matrimony — the package id kept its
   old name). Skip if they already exist.
4. In each of the two apps: *Add fingerprint* twice — the SHA-1 and the SHA-256 of the key that
   signs the APKs. The APKs are signed with the key on the build PC
   (`C:\Users\<you>\.android\debug.keystore`; print them with
   `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`):

   ```
   SHA-1:   0C:70:81:B2:C2:9E:32:D5:58:05:F3:56:CE:03:36:32:5B:79:BB:79
   SHA-256: 4A:5F:A7:39:FA:40:3E:09:A5:CB:E7:55:81:BB:04:3D:07:F4:23:46:F7:27:04:BD:E8:4A:95:C4:C8:6B:4F:EB
   ```

   **Back up that keystore file.** An APK signed with any other key cannot update the installed
   apps, and Firebase would reject its OTP requests until its fingerprints are added.
5. *Build → Authentication → Get started → Sign-in method → Phone → Enable → Save.* Then
   *Authentication → Settings → SMS region policy → Allow → India*, so nobody can run up SMS
   charges to other countries. Optional: under *Phone → Phone numbers for testing* add e.g.
   `+91 9000000001` with code `123456` — such numbers never get (or pay for) an SMS.
6. Note the settings: *Project settings → General* → **Project ID**, **Web API key**,
   **Project number** (that is the sender id), and the **App ID** (`1:…:android:…`) of each
   Android app.
7. On the VM:

```bash
cd ~/matrimony-agents/backend
nano .env     # set / add:
              # OTP_PROVIDER=firebase
              # FIREBASE_PROJECT_ID=<project id>
              # FIREBASE_API_KEY=<web api key>
              # FIREBASE_SENDER_ID=<project number>
              # FIREBASE_APP_ID_AGENT=<App ID of com.matrimonyagents.matrimony_agents>
              # FIREBASE_APP_ID_CUSTOMER=<App ID of com.matrimonyagents.gandharva>
docker compose up -d
docker compose logs api | grep "OTP provider"     # should say: OTP provider firebase
```

8. Try it: Wedbook Matrimony → enter your number → an SMS arrives (often Android reads it by
   itself). Because the APKs are not from the Play Store, Firebase may briefly open a browser page
   the first time (sometimes an "I'm not a robot" check) — that is expected. "Phone verification
   is not set up yet" in the app means one of steps 2–5 is missing (most often the fingerprints
   or the Blaze plan). To go back to test codes: `OTP_PROVIDER=mock`, `docker compose up -d`.

**Registration fee (₹150 per customer profile)** — ships with `PAYMENT_PROVIDER=mock`: the app
shows a test checkout (*Pay ₹150* / *Simulate failure*) and nothing is charged. `PROFILE_FEE_INR`
changes the amount. Each customer registers one profile (SPEC §9.17 — fixed, not an env setting).

#### Razorpay (SPEC §9.19 B)

Wedbook Matrimony **3.1.0** opens Razorpay Checkout (UPI, cards, net banking). Older apps say
"Online payment is coming soon — contact your agent" (agents can still *Mark paid (cash)*), so
switching the server first does no harm. Start in **Test mode** — no real money moves:

1. https://dashboard.razorpay.com → switch to **Test mode** (top bar) → *Account & Settings →
   API keys → Generate key*. Copy the **Key Id** (`rzp_test_…`) and **Key Secret** (shown once).
2. *Account & Settings → Webhooks → Add new webhook*: URL
   `https://YOUR_DOMAIN/api/payments/razorpay/webhook`, a **Secret** you make up (e.g.
   `openssl rand -hex 24`), events **order.paid** and **payment.captured**. (Optional but
   recommended: if a customer's app closes right after paying, the webhook still marks the
   profile paid; without it the payment is picked up the next time they open the checkout.)
3. On the VM:

```bash
cd ~/matrimony-agents/backend
nano .env     # set / add:
              # PAYMENT_PROVIDER=razorpay
              # RAZORPAY_KEY_ID=rzp_test_...
              # RAZORPAY_KEY_SECRET=...
              # RAZORPAY_WEBHOOK_SECRET=<the secret from step 2>
docker compose up -d
docker compose logs api | grep "payments razorpay"
```

4. Test: Wedbook Matrimony → *Pay ₹150* → Checkout shows a "Test mode" banner → pay with UPI id
   `success@razorpay` or a test card from https://razorpay.com/docs/payments/payments/test-card-details/
   → the profile shows as paid. The payment appears in the Razorpay dashboard (Test mode).
5. **Go live** once your Razorpay account is activated: switch the dashboard to **Live mode**,
   generate live keys (`rzp_live_…`), add the same webhook again in Live mode (webhooks are per
   mode), put the live values in `.env`, `docker compose up -d`.

**Razorpay's website / app review** asks for the link where payments are collected and a test
login (SPEC §9.19 E–F). Both are ready on the server:

- **App / website URL:** `https://YOUR_DOMAIN/` — a public page with both app downloads and the
  pages Razorpay checks: `/about`, `/contact`, `/pricing`, `/terms`, `/privacy`, `/refunds`,
  `/shipping`. The business name, address, email and phone come from `SITE_BUSINESS_NAME`,
  `SITE_ADDRESS`, `SITE_EMAIL`, `SITE_PHONE` in `.env` (use exactly what you gave Razorpay in
  KYC). Put the current APKs where the download buttons find them:

```bash
# from the PC (project folder)
scp -i ~/.ssh/<your key> wedbook-matrimony-v3.1.0.apk ubuntu@YOUR_PUBLIC_IP:~/matrimony-agents/backend/uploads/downloads/wedbook-matrimony.apk
scp -i ~/.ssh/<your key> wedbook-agent-v3.1.0.apk     ubuntu@YOUR_PUBLIC_IP:~/matrimony-agents/backend/uploads/downloads/wedbook-agent.apk
```

- **Test account:** customers log in with an SMS code, so `OTP_REVIEW_PHONE` + `OTP_REVIEW_CODE`
  make one number log in with a fixed code (no SMS). Username = that number, password = that
  code. It is the "Demo Customer" of the "Wedbook Demo Agent", with an unpaid demo profile, so
  the reviewer lands on *Pay ₹150*. Delete both demo accounts after approval (Admin → Agents /
  Customers) and empty the two `OTP_REVIEW_*` lines.

The server captures every confirmed payment itself if your account is on manual capture, and
never counts a profile twice. If a slow UPI payment completes after the customer already paid
again, the extra payment is marked `refund_due` (the admin dashboard counts them as
`refunds_due`). Find them and refund each from the Razorpay dashboard (*Payments → the payment →
Refund*):

```bash
docker compose exec db psql -U matrimony -d matrimony -c \
  "SELECT id, provider_order_id, provider_payment_id, amount_paise/100 AS rupees, note FROM payments WHERE status = 'refund_due'"
```

**Push notifications (both apps)** — off until you add the Firebase service account. The apps
already contain the push code and read the settings from the server, so **no new APK is needed**
to switch it on. Uses the same Firebase project as the phone OTP — do steps 1, 3 and 6 of
"Firebase phone OTP" above first (push itself needs no Blaze plan), then:

1. *Project settings → Service accounts → Generate new private key* → a `.json` file downloads.
   Keep it secret. Copy it to the VM and turn it into one line:

```bash
scp -i ~/.ssh/<your key> firebase-key.json ubuntu@YOUR_PUBLIC_IP:~/
ssh ... 'base64 -w0 ~/firebase-key.json; echo; rm ~/firebase-key.json'   # copy the output
```

2. On the VM:

```bash
cd ~/matrimony-agents/backend
nano .env     # the FIREBASE_PROJECT_ID / _API_KEY / _SENDER_ID / _APP_ID_AGENT /
              # _APP_ID_CUSTOMER lines from the OTP setup, plus:
              # FIREBASE_SERVICE_ACCOUNT=<the long base64 line>
docker compose up -d
docker compose logs api | grep "Push provider"     # should say: Push provider fcm
```

(The pre-v2.9 names `FCM_PROJECT_ID`, `FCM_API_KEY`, `FCM_SENDER_ID`, `FCM_APP_ID_MEDIATOR`,
`FCM_APP_ID_GANDHARVA`, `FCM_SERVICE_ACCOUNT` still work.) Then open each app once (log out and
in if it was already open) and allow notifications. Pushes follow the in-app Notifications
screens, checked every minute; the text passes through Google's servers.

**Enabling AI import ("Fill from bio-data")** — optional, and off until you do this:

```bash
nano .env          # add:  ANTHROPIC_API_KEY=sk-ant-...   (from console.anthropic.com)
docker compose up -d
```

Without a key the endpoint answers 503 and the app simply hides the button. Each parse
costs roughly ₹1–3 at the default `claude-opus-5`; set `CLAUDE_MODEL=claude-haiku-4-5`
in `.env` for ~5× cheaper. Bio-data documents are sent to Anthropic for extraction and are
not stored on the server — tell your agents that before they use it.

## 12. Keeping the free VM

Oracle reclaims *idle* Always Free instances. Daily use plus the nightly backup cron keeps
it above the idle threshold. Upgrading the account to Pay-As-You-Go removes reclamation
entirely and still costs ₹0 while you stay inside Always Free limits — recommended once
real agents depend on it.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `curl https://…` fails, TLS error | DNS hasn't propagated. `dig +short your-domain.example.com` must show your VM IP, then `sudo systemctl restart caddy`. |
| `502 Bad Gateway` | API isn't up. `docker compose ps` and `docker compose logs api`. |
| `{"ok":false,"error":"db_unreachable"}` | Database still starting, or a wrong `DB_PASSWORD` in `.env`. `docker compose logs db`. |
| Share links open `localhost` | `PUBLIC_BASE_URL` is wrong in `.env`. Fix it and `docker compose up -d`. Links already sent stay broken. |
| Build fails on `bcrypt` with node-gyp errors | The prebuilt ARM64 binary couldn't be downloaded (GitHub unreachable). Add `RUN apk add --no-cache python3 make g++` above `npm install` in the `Dockerfile` and rebuild. |
| Watermark/card text missing on shared images | Fonts absent from the image. The `Dockerfile` installs `font-dejavu`; confirm the build didn't skip it: `docker compose exec api fc-list \| head`. |
| Photos upload but never display | `uploads/` permissions. `ls -la ~/matrimony-agents/backend/uploads`, and confirm the volume line in `docker-compose.yml`. |
| Agent says "Cannot reach the server" | APK built with the wrong `API_BASE_URL`, or built against `http://`. Rebuild per step 10. |
| Too many login attempts (429) | The limiter allows 50 per 15 minutes per IP. It resets on its own; `docker compose restart api` clears it immediately. |

---

## What has been tested

Everything below was executed and verified locally with Docker before this guide was written:

| Verified | How |
|---|---|
| `docker compose up -d --build` brings up both services healthy | Ran; API healthy, db healthy |
| API reachable only on loopback | `docker compose ps` shows `127.0.0.1:3000->3000/tcp`; db publishes no host port |
| `schema.sql` auto-applies on first start | Fresh volume → 3 communities, 27 nakshatrams, 12 rasis, 16 educations |
| All 248 business-rule checks against the containerised stack | `npm run smoke` → 248/248 |
| **arm64 image builds** (the Oracle VM's architecture) | `docker buildx build --platform linux/arm64` |
| **arm64 native modules load and work** | `bcrypt` hash+verify and `sharp` 0.33.5 / libvips 8.15.3 loaded inside the arm64 container |
| **arm64 font rendering** (watermarks, share cards) | Rasterised text inside the arm64 image — 22 fonts present, text produced real pixels |
| `backup.sh` produces both artifacts | db `.sql.gz` + uploads `.tgz` (63 entries) |
| The backup actually **restores** | Restored the dump into a scratch database; all tables and rows intact |
| `docker compose down -v && up -d` resets cleanly | 4 agents → 1 (default admin), 0 profiles, seed data back |

**Not tested here, because they need your account and domain:** Oracle VM creation and
security lists, DNS propagation, and Caddy obtaining a real certificate. Steps 1, 2, 3 and 5
are the parts to watch — the troubleshooting table above covers their usual failures.
