# Scalability and Cost Analysis

> **All numbers are assumptions for planning, not quotes.** Supabase, SMS and egress prices were **not** checked online in this session. Check the current pricing pages before budgeting. Free tiers are for testing only.

## Usage assumptions (per DAU per day)

| Action | Count | Approx. payload |
|---|---|---|
| Explore searches / pages | 6 | 8 KB (20 cards) |
| Venue detail views | 3 | 6 KB + ~3 signed photo URLs |
| Review list pages | 2 | 6 KB |
| Favorites toggles | 0.3 | <1 KB |
| Reviews submitted | 0.05 (1 in 20 users) | 1 KB + 0.5 photos × 400 KB |
| Venue submissions | 0.005 | 2 KB + 1 photo |
| Photo views | 4 | 150 KB each (resized) |
| Auth refresh | 2 | <1 KB |

## Estimates

| DAU | RPC reads/day | Writes/day | New media/month | Media egress/month | DB size after 1 yr | Notes |
|---|---|---|---|---|---|---|
| 100 | ~1.3k | ~40 | ~0.6 GB | ~1.8 GB | < 200 MB | Smallest paid tier is ample; free tier fine for a demo |
| 1,000 | ~13k | ~400 | ~6 GB | ~18 GB | < 1 GB | Still a small instance; watch SMS OTP cost (≈ one OTP per new Registered user) |
| 10,000 | ~130k (~1.5 rps avg, ~15 rps peak) | ~4k | ~60 GB | ~180 GB | a few GB | Enable connection pooling (Supavisor transaction mode); image CDN/transforms; `EXPLAIN` the search RPC |
| 100,000 | ~1.3M (~15 rps avg, ~150 rps peak) | ~40k | ~600 GB | ~1.8 TB | tens of GB | Larger compute, read replica for search, trigger-maintained stats table, storage lifecycle rules, dedicated moderation tooling |

Main cost drivers, in order: **media egress and storage**, then **SMS OTP**, then compute. Ways to reduce them: resize to ≤ 2048 px and JPEG q≈0.8 on device (implemented), serve thumbnails, cache signed URLs for up to 1 hour, and send OTP only when the user chooses to register.

## Staged scaling

1. **Now:** indexes, bounded queries, rate limits (challenges, open submissions), storage size/MIME limits. All implemented.
2. **When measured:** pooling, a `venue_stats` table, CDN image transforms, and background moderation jobs.
3. **Only with metrics:** read replicas, partitioning `review_revisions` / `analytics_events` by time, or a dedicated search service.

## Operational workload

The main recurring cost in people's time is Admin moderation, estimated at about 1–3 minutes per submission. With the cold-start plan (one campus or district, curated seed) the queue stays small. A web console becomes worthwhile at more than about 50 submissions a day.
