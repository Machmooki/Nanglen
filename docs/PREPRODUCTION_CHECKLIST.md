# Pre-production checklist

Project: **Nanglen** (`tuufgzbgldtkwaqqxyur`, ap-northeast-1, production). Checked 2026-11-16/17.

## 1. What the remote looks like (read-only checks)

| Check | Result |
|---|---|
| CLI linked | Yes, `supabase/.temp/project-ref = tuufgzbgldtkwaqqxyur` |
| Migration history (`supabase migration list`) | **Empty**: all 10 local migrations show as "not applied" |
| Actual schema | **All 10 migrations are applied** (applied by hand in the SQL Editor). Confirmed by markers: tables, RPCs, 0008 settings, `venue_media.kind` (panorama), `profiles.avatar_path` + `set_my_avatar()` (avatar), and all 3 buckets |
| Edge Function `delete-account` | Deployed, ACTIVE, version 1, `verify_jwt = true` |
| Demo / test data | **None.** 0 venues, 0 users (anonymous or registered), 0 Storage files. The seed was never run on remote |
| Unit-test runs | Created no remote users (count still 0 afterwards) |

Counts come from `supabase/scripts/preprod_counts.sql` (read-only; rerun any time):

```bash
supabase db query --remote --read-only -f supabase/scripts/preprod_counts.sql
```

## 2. Cleanup scripts (prepared, not run, nothing to delete today)

| File | What it does |
|---|---|
| `supabase/scripts/preprod_counts.sql` | Read-only counts of demo venues, linked rows in every FK table, test users (`@demo.nanglen.app`, `@example.test`, `@example.com`), empty anonymous users, and Storage files |
| `supabase/scripts/preprod_storage_paths.sql` | Read-only list of the Storage files tied to that data |
| `supabase/scripts/preprod_storage_cleanup.ts` | Deno script. **Dry run by default**, `--apply` to delete. Uses `SUPABASE_SERVICE_ROLE_KEY` from your shell env only, and touches only paths from the JSON file (bucket and path-shape allowlist) |
| `supabase/scripts/preprod_cleanup.sql` | One transaction. Shows BEFORE counts, then deletes in safe order: analytics, then submissions pointing at demo venues (a CHECK would block otherwise), then venues (CASCADE), then test users, then empty anonymous users. Shows AFTER counts. **Ends with ROLLBACK**; change it to COMMIT only after a reviewed dry run. Test users that appear in the append-only audit trail are skipped, never edited |

Order if it's ever needed:
1. Back up: `supabase db dump --linked --data-only -f backup_preprod.sql`
2. Storage paths, then the storage dry run, then `--apply`
3. SQL dry run, then COMMIT

`venue_rating_summaries` and `venue_tag_counts` are plain views, so there's nothing to refresh.

The cleanup SQL was **not executed**, even as a dry run, because it contains DELETE statements and the rule says to wait for your confirmation. Its syntax is therefore unverified.

## 3. Keeping test data out

- `supabase/config.toml` `[db.seed]` applies to the **local** stack only. `supabase db push` doesn't run it (unless `--include-seed`). **`supabase db reset --linked` wipes production and runs the seed: never use it.** A comment now says so in the file.
- Demo admin (`DemoSeed.adminEmail`): used only in `DemoBackend.defaultAdminEmails` and the sign-in hint, both under `#if DEBUG`. The hint is shown only in Demo mode. `SupabaseBackend` never references `DemoSeed`.
- Wikimedia photos and 360° panoramas: `DemoSeed.photoURLs` / `panoramaURL` are read only by `DemoBackend`, and the "https path passes through" shortcut exists only in `DemoBackend.signedMediaURLs`. `SupabaseBackend` only signs real Storage paths.
- Tests and UI tests: the app now forces `DemoBackend` when running under XCTest (`XCTestConfigurationFilePath`) or with `-NanglenDemoBackend`, so tests never create anonymous users on production.

## 4. App ↔ real Supabase

| Item | Status |
|---|---|
| `Config/Supabase.example.plist` | Placeholders now (`https://YOUR_PROJECT_REF.supabase.co`, `YOUR_PUBLISHABLE_KEY`) with corrected comments. ⚠️ The real URL and publishable key are in git history (commit `c28631d` and earlier). Publishable keys are designed to be public (RLS protects the data), so rotation is optional |
| `Nanglen_App/Resources/Supabase.plist` | Created with the base URL `https://tuufgzbgldtkwaqqxyur.supabase.co` (no `/rest/v1/`) and the publishable key. Git-ignored (verified), bundled into the app (verified in the built `.app`) |
| `SupabaseConfiguration.load()` | Now trims whitespace, strips a trailing `/` and a pasted `/rest/v1` / `/auth/v1` / `/storage/v1`, requires https (http only for localhost), and rejects placeholders, `sb_secret_…` keys and service-role JWTs. Covered by 3 new unit tests |
| Email OTP length | `AppConfiguration.emailOTPLength = 6` (the sign-in screen auto-submits at 6 digits). **Remote is currently 8**, see section 5 |

## 5. Remote changes (run 2026-11-17 after your confirmation)

| Step | Result |
|---|---|
| `supabase migration repair --remote --status applied` (10 versions) | ✅ Done. `migration list` shows all 10 as applied, so `supabase db push` is now a no-op until a new migration is added |
| `supabase config push` | ⚠️ Partly done. API: `max_rows` 100, only the `public` schema exposed. Auth: `otp_length` **6**, `otp_expiry` 600, `double_confirm_changes` false, `secure_password_change` true, `site_url` `nanglen://auth`, SMS confirmations off. Storage: file size limit 5 MiB |
| Email templates (`email_change`, `magic_link` → 6-digit code, `supabase/templates/email_otp.html`) | ✅ Done 2026-11-17, after custom SMTP (Gmail SMTP, dedicated sender account) was configured in the dashboard. `supabase config diff` shows no differences for any declared setting |

SMTP credentials live only in the dashboard (they're remote-only and deliberately not in `config.toml`). Gmail SMTP sends ≈500 emails/day; move to an own domain + Brevo/Resend before a larger launch.

**Troubleshooting "Send code" (2026-11-17).** Auth logs showed `PUT /user` → 500 `535 5.7.8 Username and Password not accepted` (Gmail refused the SMTP login), then 429 `over_email_send_rate_limit`. The Swift SDK retries a 500 on `PUT` twice, so each tap made 3 SMTP attempts and quickly used up the hourly email quota. Fix: create a new App Password on the **sender** Gmail account (2-Step Verification on), paste it into Dashboard → Authentication → Emails → SMTP Settings → Password, and save. Then wait for the quota to reset, or raise it under Authentication → Rate Limits. The app now shows "We couldn't send the code email…" for this case and logs the raw Auth error to the Xcode console (category `Auth`). To read the logs yourself:

```bash
supabase logs --remote --sql "select timestamp, event_message from logs where source = 'auth_logs' order by timestamp desc limit 40"
```

Not changed (exist on remote only, not declared locally): MFA TOTP enabled, pooler sizes, redirect URLs. `delete-account` is already deployed; redeploy with `supabase functions deploy delete-account --use-api` only if it changes.

## 6. First production Admin

1. Install the build that uses `Supabase.plist`, then Profile → **Verify email** with your own address.
2. Dashboard → Authentication → Users → copy your user UUID.
3. In the SQL Editor (runs as an owner role):
   ```sql
   select private.grant_admin('<your-user-uuid>', 'ops:machmooki', 'initial production admin');
   ```
4. Reopen Profile: it shows "Administrator" and the **Team review queue** row.
5. To revoke: `select private.revoke_admin('<uuid>');`. Admins can't delete their own account until revoked.

## 7. Manual test on a device

- [ ] Open the app → Profile → Settings → **Server** shows `tuufgzbgldtkwaqqxyur.supabase.co` (not "Demo mode")
- [ ] Explore is empty (or shows only real places); there are no "(Demo)" places
- [ ] Profile → Verify email → you receive a **6-digit code** (not a link) → after verifying you're a Member with a masked email
- [ ] Suggest a new place → it's "Pending review" in My suggested places, and **not** visible in Explore yet
- [ ] (As Admin) Team review queue → approve → the place appears in Explore
- [ ] On the venue: Write a review (be within 100 m; location verification) → it's published and the rating updates
- [ ] Profile → set a profile photo → it shows after reopening the app
- [ ] Sign out / sign in with the same email → your data comes back
- [ ] Delete account → you're a new Guest; your review and suggestion are gone (approved place stays)

## 8. Release fallback (proposal, not applied)

Today a build **without** `Supabase.plist` silently runs the Demo backend. That's fine for Debug, but risky for Release. Smallest options:

- **A (≈5 lines, recommended):** in `AppContainer.live()`, under `#if !DEBUG`, stop with a clear `fatalError("Supabase.plist missing or invalid …")` when the config can't be loaded and `-NanglenDemoBackend` isn't set. A misconfigured TestFlight build fails on first launch, so it never reaches users silently.
- **B (≈1 build phase):** a Run Script that fails a **Release** build when `Nanglen_App/Resources/Supabase.plist` is missing. The safest, but it needs a `project.pbxproj` edit.
