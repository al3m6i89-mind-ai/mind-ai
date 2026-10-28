# Nuvola · cloud Android phones

Working name; the brand can change before launch.

| Folder | What it is |
| --- | --- |
| `backend/` | Kotlin + Spring Boot API, PostgreSQL (Flyway migrations), device job queue |
| `android/` | Kotlin + Jetpack Compose app, Arabic and English with RTL |
| `docker-compose.yml` | Local PostgreSQL, Redis and API |
| `.github/workflows/ci.yml` | Backend tests and a debug APK build on every push |

## What is real and what is not yet

Real and tested:

- Accounts: register, sign in, email confirmation codes, password reset, sign-out, account deletion with a 14-day grace period.
- Sessions: 15-minute access tokens, rotating refresh tokens, reuse detection that signs out every device, rate-limited sign-in.
- Plans, subscriptions, device limits, ownership checks, an audit log, support tickets.
- Device lifecycle (create, start, stop, restart, root on/off, delete) through a database job queue
  that survives restarts, with idempotent creation so a double tap never makes two phones.
- Android version chosen by the user from images the server actually has; root as a per-phone option.

Not real yet:

- **No Android runs anywhere.** The only installed device provider is `mock`, which walks phones through
  states with a delay. The API and the app label these phones "Simulated". The server refuses to start in
  production with this provider.
- **No screen streaming.** Opening a phone returns `STREAMING_NOT_AVAILABLE`. Phase 4 adds the stream gateway,
  the on-host device agent and the video/touch client.
- **No payments.** Development servers can activate a plan without paying (`provider = dev-unpaid`);
  production returns `PAYMENT_REQUIRED`. Phase 5 adds Google Play Billing or an approved provider.
- Google sign-in, push notifications and the admin dashboard are not built yet.

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
