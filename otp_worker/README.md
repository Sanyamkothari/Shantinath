# OTP Worker (Cloudflare Workers, free tier)

Replaces the `sendOtp` / `verifyOtp` Cloud Functions so the Firebase project can
stay on the **Spark** plan. Same request/response contract:

- `POST /sendOtp   { phone, requireRegistered? }` → `{ success, verificationId }`
- `POST /verifyOtp { phone, verificationId, otp }` → `{ success, customToken }`

Verification sessions and send quotas live in Cloudflare D1; Firestore is only
read over REST to check that `users/{phone}` exists. The Firebase custom token is
signed in the Worker with your service-account key.

## One-time setup

```bash
cd otp_worker
npm install

wrangler login

# 1. Database
wrangler d1 create shantinath-otp          # copy the printed database_id into wrangler.toml
wrangler d1 execute shantinath-otp --remote --file=schema.sql

# 2. Secrets
wrangler secret put MC_AUTH_TOKEN          # MessageCentral VerifyNow auth token
wrangler secret put FIREBASE_SA_KEY        # paste the ENTIRE service-account JSON

# 3. Deploy
wrangler deploy                            # prints https://shantinath-otp.<you>.workers.dev
```

Service-account key: Firebase Console → Project settings → Service accounts →
*Generate new private key*. Never commit it; delete the downloaded file once it
is stored as a secret.

## Point the app at it

Set `AppConstants.otpApiBaseUrl` in `lib/config/constants.dart` to the printed
URL, or build with `--dart-define=OTP_API_BASE_URL=https://shantinath-otp.<you>.workers.dev`.

## Notes

- Free-tier limits: 100k requests/day, 5M D1 reads/day, 100k D1 writes/day.
- A daily cron (`wrangler.toml`) deletes expired sessions and rate-limit rows.
- Tail logs with `wrangler tail`.
