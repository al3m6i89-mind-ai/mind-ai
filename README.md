# Nuvola · cloud Android phones

Working name; the brand can change before launch.

| Folder | What it is |
| --- | --- |
| `backend/` | Kotlin + Spring Boot API, PostgreSQL (Flyway migrations), device job queue |
| `android/` | Kotlin + Jetpack Compose app, Arabic and English with RTL |
| `node-agent/` | Go agent for a phone server: runs Android in Redroid containers and streams screens |
| `docker-compose.yml` | Local PostgreSQL, Redis and API |
| `.github/workflows/ci.yml` | Backend tests, APK builds, an emulator launch check and a real-phone end-to-end test |

## What is real and what is not yet

Real and tested:

- Accounts: register, sign in, email confirmation codes, password reset, sign-out, account deletion with a 14-day grace period.
- Sessions: 15-minute access tokens, rotating refresh tokens, reuse detection that signs out every device, rate-limited sign-in.
- Plans, subscriptions, device limits, ownership checks, an audit log, support tickets.
- Device lifecycle (create, start, stop, restart, root on/off, delete) through a database job queue
  that survives restarts, with idempotent creation so a double tap never makes two phones.
- Android version chosen by the user from images the server actually has; root as a per-phone option.
- **Real Android phones** (provider `redroid`): Android 12, 13 and 14 in Redroid containers on a phone server,
  with Google Play (MindTheGapps) and, when root is on, Magisk. Root on/off swaps the system image and keeps the
  phone's data. CI boots a phone on x86 and ARM, checks Google Play and Magisk, and drives the whole flow
  through the backend.
- **Live screen and touch**: the app opens a session on the backend, which signs a 60-second ticket; the app
  then connects to the phone server directly (WebSocket over HTTPS), decodes H.264 with MediaCodec and sends
  multi-touch and Back/Home/Recents as scrcpy control messages.

Not real yet:

- Without a phone server the backend uses the `mock` provider (labelled "Simulated" in the app).
  Production refuses to start with it.
- One phone server per backend for now; several servers and regions come with the admin dashboard.
- No audio from the phone, and no per-phone storage limit (the plan's storage is shown but not enforced).
- **No payments.** Development servers can activate a plan without paying (`provider = dev-unpaid`);
  production returns `PAYMENT_REQUIRED`. Phase 5 adds Google Play Billing or an approved provider.
- Google sign-in, push notifications and the admin dashboard are not built yet.

## Set up a phone server

Any Ubuntu 22.04/24.04 server with a full kernel (not a container VPS), x86_64 or ARM, for example
Oracle Cloud's free Ampere A1 (4 cores, 24 GB). Open TCP 80 and 443, then as root:

```bash
curl -fsSL https://raw.githubusercontent.com/al3m6i89-mind-ai/mind-ai/nuvola-cloudphone/node-agent/install.sh | sudo bash
```

It builds the Android images, starts the agent behind HTTPS (Caddy, with a `<ip>.sslip.io` name) and prints
`REDROID_NODE_URL` and `REDROID_NODE_TOKEN`. Set both on the backend; with `DEVICE_PROVIDER=auto` it switches
from simulated to real phones.

## Run the backend

```bash
docker compose up --build        # API on http://localhost:8080
# or, with a local PostgreSQL:
cd backend && ./gradlew bootRun
```

API docs: http://localhost:8080/api/v1/docs (disabled in production). In development, emails are printed
to the server log, including the confirmation code.

Tests need PostgreSQL with a `nuvola_test` database owned by `nuvola/nuvola`:

```bash
cd backend && ./gradlew test
```

## Run the Android app

Open `android/` in Android Studio and run the `devDebug` variant on an emulator. It talks to
`http://10.0.2.2:8080`, which is your computer from inside the emulator. `staging` and `prod`
flavors use HTTPS only.

## Environments

| Variable | Purpose |
| --- | --- |
| `SPRING_PROFILES_ACTIVE` | `dev`, `staging` or `prod` |
| `DATABASE_URL`, `DATABASE_USER`, `DATABASE_PASSWORD` | PostgreSQL |
| `JWT_SECRET` | Random, at least 32 characters (required in production) |
| `DEVICE_PROVIDER` | `mock` in development only |
| `MAIL_TRANSPORT`, `SMTP_*`, `MAIL_FROM` | Real email in staging and production |
| `TERMS_URL`, `PRIVACY_URL`, `SUPPORT_EMAIL` | Shown in the app |
