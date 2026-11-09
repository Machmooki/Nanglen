# Location Verification Design

## Flow

```
App (Registered user taps "เขียนรีวิว")
 1. Location permission requested NOW if not determined (never at launch)
 2. issue_visit_challenge(venue)            → {challenge_id, expires_at (120 s), thresholds}
 3. Fresh CLLocation (kCLLocationAccuracyBest, one-shot, up to 3 attempts while accuracy improves
    or the reading predates the challenge)
 4. Client pre-check (VisitReadingEvaluator) for UX only
 5. verify_visit(challenge, lat, lng, horizontalAccuracy, timestamp)
      server: challenge belongs to caller · not consumed · not expired → mark consumed
              timestamp ≤ now+5 s, ≥ issued_at−5 s, now−ts ≤ 60 s      else stale/invalid
              0 ≤ accuracy ≤ 50 m                                         else inaccurate
              ST_Distance(venue, reading) ≤ 100 m                         else too_far
      stores status + distance/accuracy buckets only (no coordinates)
      → verification_id (only if verified), expires in 15 min
 6. Form unlocks; submit_review(..., verification_id, idempotency_key)
      consumes the verification in the same transaction that writes the revision
```

UI states (`VerificationState` → `VerificationStatusView`): requesting permission, checking location, verifying, **verified**, too far (with approximate distance), inaccurate (move near a window and retry), stale, unavailable, permission denied (Open Settings), registration required (link phone), failed (retry).

## Thresholds

`private.app_settings`: `visit_radius_m=100`, `visit_max_accuracy_m=50`, `visit_max_location_age_s=60`, `visit_clock_skew_s=5`, `visit_challenge_ttl_s=120`, `visit_verification_ttl_s=900`, `visit_challenges_per_10min=10`. They are starting values; change them with an UPDATE (no deploy). The app reads them through `get_public_config` / the challenge response for its pre-check; the server decision is authoritative.

## Replay and reuse protection

| Attack | Defence | Test |
|---|---|---|
| Replay a verify call | challenge consumed on first evaluation | `challenge_consumed` (SQL + Swift) |
| Use someone else's challenge | `user_id = auth.uid()` lookup | `challenge_not_found` |
| Use an old cached reading | reading must be newer than challenge − skew and ≤ 60 s old | `stale` |
| Reuse a verification for a 2nd review / other venue | `UNIQUE(visit_verification_id)` + venue/user match + `consumed_at` | `verification_consumed`, `verification_invalid` |
| Submit long after verifying | verification TTL 15 min | `verification_expired` |
| Double-tap / retry submit | `UNIQUE(user_id, idempotency_key)` → replay returns original | `replayed = true` |
| Spam challenges | 10 per 10 min per user | `rate_limited` |

## Honest limitation

Core Location values are **client-supplied**. Server checks validate the *submitted* coordinates, not physical presence; a modified device can spoof GPS. Nanglen never calls this proof of attendance. Hardening (Planned): Apple App Attest assertion on `verify_visit` (Edge Function validates; stored as `integrity_status`), anomaly detection (impossible travel, many venues per hour), optional venue QR/NFC (`method` column already allows `qr`/`nfc`).

## Privacy

No continuous tracking, no background location, no coordinate storage. Only `distance_bucket` (0-25/25-50/50-100/100-250/250+) and `accuracy_bucket` are kept for monitoring false rejections.

## Indoor / mall handling

Up to three readings are taken and the most accurate is sent. Inaccurate readings show a specific retry message instead of being downgraded. Monitor `too_far`/`inaccurate` rates per venue; tune radius per venue later (e.g. a `venues.verification_radius_m` override) if multi-floor venues show high false rejection.
