# Features and User Flows

Status: **Verified in simulator** means I walked through it manually on the iPhone 17 simulator (iOS 27) against the Demo backend on 2026-11-09. **Tested** means it is covered by automated tests that pass.

## Navigation

Tab bar (Main.storyboard): **สำรวจ (Explore) · บันทึกไว้ (Saved) · โปรไฟล์ (Profile)**. The secondary flows are storyboard scenes too: Venue Detail, Filter, Review Composer, Phone Link, Add Place, My Submissions, Admin Queue and detail, Claim. The only programmatic screen is the transient Apple Maps candidate sheet.

## Guest

| Flow | Behaviour | Status |
|---|---|---|
| First launch | No sign-up screen and no location prompt. An anonymous session is created in the background. | Verified in simulator |
| Filters | Filter sheet: **Good for** chips (Study-friendly, Quiet, Good Wi-Fi, Power outlets, … up to 3), **Only places with reviews**, sort, distance, minimum rating. Active filters appear under the search bar as removable chips with **Clear all**; matched tags show first on each card. | Verified in simulator; Tested |
| Explore | Search bar first. Category chips (ทั้งหมด, คาเฟ่, ห้องสมุด, Co-working, Study Space, อื่น ๆ). Small filter button (sort, distance, minimum rating). List/map toggle. "Recommended in this area" list. Cards show name, category · distance, rating badge (★ 4.3 · 3 รีวิว or "ยังไม่มีรีวิว"), top community tags, and a note that tags come from users. | Verified in simulator |
| Search | Debounced and stale-safe. Only approved Nanglen venues. Paginated. "ไม่เจอที่ที่หา?" footer leads to Add Place. | Implemented; ranking logic Tested |
| Venue detail | Map, name, category, distance, rating and count, address, Directions (Apple Maps), Write review, community tags with counts, reviews (relevant/recent, load more, report), official details only when their source is known, claim entry. | Verified in simulator |
| Save | The heart on detail saves to the anonymous account. Saved shows a note that verifying an email keeps the list across devices. | Implemented; backend rule Tested |
| Write a review | An alert explains that a verified email is needed and offers to verify one. No form is shown. | Verified in simulator; UI test |

## Registered user (free email code)

| Flow | Behaviour | Status |
|---|---|---|
| Verify email | Profile, or the prompt from a gated action → email → 6-digit code (auto-submits when complete) → same user id kept, favorites stay. If the email already has an account, the app asks to **Sign in** to it instead (no merge). In Demo the code is `123456`. | Verified in simulator; Tested |
| Delete account | Profile → Delete account → confirm → account, reviews, saved places, suggestions and photos are deleted; a fresh Guest session starts. | Implemented; Tested (Demo) |
| Review | Write review → permission asked only now → challenge → fresh GPS → server verification → "ยืนยันการไปจริงแล้ว" → stars (required), purpose, ≤ 3 tags, ≤ 500 chars, ≤ 3 photos → publish. Failure states have retry, Open Settings or link phone. A revisit gives "อัปเดตรีวิว" and creates a new revision. | Verified in simulator (4★ review published; rating went from 4.3·3 to 4.2·4); rules Tested |
| Add place | Profile/Explore → Apple Maps search (results marked "not on Nanglen yet" or "already on Nanglen") or pin → name, category, address (+ optional fields and photos) → "ส่งแล้ว · รอทีมงานตรวจสอบ", with duplicate hints. | Verified in simulator; Tested |
| My submissions | Status, Admin feedback, withdraw, edit & resubmit when changes are requested, open venue when approved or marked duplicate. | Implemented; resubmit rule Tested |
| Claim a venue | Detail → claim form → pending. Rights are granted only after Admin approval, and only for that venue. | Implemented; Tested |

## Admin (server-authorized)

| Flow | Behaviour | Status |
|---|---|---|
| Entry | The Profile row "คิวตรวจสอบของทีมงาน" appears only when `is_admin` comes from the server. In Demo (debug builds only), verifying `admin@demo.nanglen.app` grants Admin. | Verified in simulator |
| Venue submissions | List → detail (map, data, submitter stats, photos, duplicate candidates, history) → Approve (optional note; likely duplicates need "approve anyway"), Request changes, Reject (reason required), Mark duplicate (pick candidate). Each action is audited. | Verified in simulator (approved "Study Loft" → venue created, audit row); Tested |
| Claims | Approve or reject (reason required) | Implemented; Tested |
| Flagged reviews | Dismiss, hide or remove (reason required) | Implemented; Tested |

## Not implemented / planned

- Admin UI for approving review photos (the RPCs exist).
- Business tools beyond the claim: change requests UI, owner responses, analytics.
- App Attest, an analytics dashboard, a web moderation console.
- English localisation (strings are centralised in `L10n` and the String Catalog).
