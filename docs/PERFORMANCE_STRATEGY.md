# Performance Strategy

## Query design

- **Explore** calls one RPC, `search_venues`, which returns compact cards: id, name, category, address, coordinates, status, count/average, top 3 tags, cover path, distance, score. It never returns review bodies. `limit` ≤ 50 and `offset` ≤ 500. The app asks for `limit + 1` rows to know whether more exist.
- Browsing (no text) is area-bounded with `ST_DWithin(location, origin, radius)` on the GiST index. A text search is filtered with `strpos` / `pg_trgm` similarity on `normalized_name` (GIN trigram index), and distance is used only for ranking.
- Top tags and the cover photo are computed **after** the page is cut, so the correlated subqueries run at most 50 times.
- **Venue detail** is one `get_venue` call (summary, distribution, tag counts, photos, own review) plus one paged `list_venue_reviews` call. Photos use a single batched `createSignedURLs` call.
- **Saved** makes one `my_favorite_venue_ids` call plus one `get_venue_cards` call per 100 ids. There is no N+1 pattern.
- **Apple Maps candidates** are mapped in one `match_provider_refs` call (≤ 100 ids).

## Ranking (in SQL, mirrored by `VenueRanker` for offline re-sorting)

```
bayes     = (C·m + Σratings)/(C + n)      C = rank_prior_weight (5), m = rank_prior_mean (3.5)
quality   = (bayes − 1)/4
proximity = 1/(1 + distance_km)           (0.5 without origin)
relevance = max(trigram similarity, word similarity, 0.9 prefix / 0.7 substring)
score     = 0.50·relevance + 0.25·quality + 0.25·proximity   (text search)
          = 0.55·quality + 0.45·proximity                    (browse)
```

The UI shows the plain average and count. Sort options are relevance (default), distance, and rating (Bayesian, then review count). Ownership and payment are not inputs.

## Indexes (and why)

| Index | Serves |
|---|---|
| `venues_location_gix` (GiST) | radius browse, duplicate candidates, distance |
| `venues_normalized_name_trgm` (GIN) | text search, duplicate name similarity |
| `venues_status_category_idx` | category chips |
| `venue_provider_refs (provider, external_place_id)` unique | exact provider matching |
| `reviews_venue_updated_idx` partial (published) | review lists, summaries |
| `reviews (venue_id, user_id)` unique | one current review / upsert |
| `review_revisions (review_id, revision_number desc)` | revision numbering |
| `favorites (user_id, created_at desc)` | Saved |
| `venue_submissions (submitted_by, created_at desc)`, partial `(submitted_at) where pending_review` | My Submissions, Admin queue |
| `business_memberships (user_id,status)`, `(business_id,status)` | capability checks |

Write cost is small: reviews and submissions are low-volume, so the extra indexes are acceptable.

## Client

- Search is debounced by 350 ms, one-character queries are skipped, and stale responses are dropped using a generation counter and task cancellation.
- Changing filters triggers a single bounded request. Infinite scroll loads the next page near the end of the list.
- The cache renders offline results immediately with a stale label.

## To do once a real database is available

Run `EXPLAIN (ANALYZE, BUFFERS)` on `search_venues` against about 10k venues and 200k reviews. If the `venue_rating_summaries` aggregation dominates, add a trigger-maintained `venue_stats` table. Do not add a materialized view before measuring.
