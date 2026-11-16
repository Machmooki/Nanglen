# Production Deployment

## Environments

Use three Supabase projects: **local** (`supabase start`), **staging**, and **production**. Each has its own keys. The iOS app picks its backend from `Nanglen_App/Resources/Supabase.plist` (git-ignored) or from the `SUPABASE_URL` / `SUPABASE_ANON_KEY` environment variables. With neither present it runs the **Demo backend**, which is labelled "โหมดสาธิต" in the UI.

## Local development

```bash
cd Nanglen_App
supabase start            # needs Docker
supabase db reset         # applies migrations + seed.sql
supabase test db          # runs supabase/tests/database/*.test.sql (pgTAP)
```

> In this session the pgTAP suite was **written but not run** (no Docker or Postgres available). Run it before the first deploy.

## Steps for staging and production

1. Create the project in a region close to Thailand (e.g. Singapore).
2. `supabase link --project-ref <ref>` then `supabase db push` to apply the 8 ordered migrations (0001 → 0008). **Do not** run `seed.sql` in production.
   Deploy the account-deletion function: `supabase functions deploy delete-account` (needs no secrets beyond the defaults Supabase injects).
3. **Auth (free — no SMS):** Dashboard → Authentication
   - **Sign In / Providers → Anonymous sign-ins: ON** (Guests). Turn on **CAPTCHA** (Cloudflare Turnstile is free) under Attack Protection.
   - **Email: ON, Confirm email: ON**, OTP length 6, OTP expiry 600 s. **Phone: OFF** (SMS is billed). Manual linking: ON.
   - **Email Templates → "Change email address" and "Magic link"**: paste `supabase/templates/email_otp.html` (it shows `{{ .Token }}`, the 6-digit code — the app expects a code, not a link).
   - **SMTP:** the built-in sender only delivers to your project's team members and is heavily rate-limited. For real users add a free SMTP sender (e.g. Brevo free tier ≈ 300 emails/day, or a Gmail account with an app password) under Authentication → SMTP Settings.
   - Rate limits: keep the defaults or lower (emails/hour, token verifications per 5 min) to slow brute-force and spam.
4. **Storage:** create the private buckets `venue-submission-media` and `review-media` (5 MiB, `image/jpeg, image/png, image/heic, image/webp`) using the dashboard, CLI or Storage API. The policies come from the migration.
5. **API:** keep `public` as the only exposed schema. Never add `private` or `extensions`.
6. **First Admin:** in the SQL editor, which runs as the service role, run:
   ```sql
   select private.grant_admin('<auth user uuid>', 'ops:<your name>', 'initial admin');
   ```
   To revoke: `select private.revoke_admin('<uuid>');`. The user must be Registered (email confirmed) to act as Admin. Find the uuid under Authentication → Users after verifying your email in the app.
7. **Curated launch data:** import the venues for one area using an admin-only SQL script with `provenance = 'curated_import'`, `details_source = 'admin_curated'` and provider refs.
8. **iOS:** copy `Config/Supabase.example.plist` to `Nanglen_App/Resources/Supabase.plist` and add the **anon or publishable key only**, then build. Profile should show the host name instead of "Demo".

## Operations checklist

- Versioned migrations only. Make changes additive, and never reset production.
- Back up daily, turn on PITR for production, and **test a restore** every quarter.
- Monitoring: database CPU and connections, slow queries (`pg_stat_statements`), auth error rate, email sends vs. SMTP quota, storage growth, verification outcome ratios (`private.visit_verifications.status`), and queue age (`venue_submissions` pending older than 48 h).
- Error tracking in the app: add Sentry or Crashlytics before launch (**Planned**).
- Secret rotation: rotate the anon/publishable key if it leaks. The service role key stays only in CI and the SQL editor.
- Privacy: write a data deletion runbook (deleting the `auth.users` row cascades profile, favorites, reviews, submissions and media metadata, but Storage objects must also be removed through the API). Get a PDPA review before commercial launch.
- Incident response: name an owner, set severity levels, and document how to disable anonymous sign-ins or set the review RPC to read-only through `app_settings` or by revoking grants.
