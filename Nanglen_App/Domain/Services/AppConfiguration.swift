// Where to change limits
// ----------------------
// The real values live in Supabase, table `private.app_settings` (Dashboard → Table editor → schema
// "private" → app_settings, or SQL: `update private.app_settings set value = '8' where key = 'review_max_photos';`).
// The server enforces them, and `get_public_config()` sends the UI-relevant ones to the app.
// `RemoteConfigService` loads that config at launch, caches it, and merges it over the defaults below,
// so a change in Supabase reaches users the next time they open the app — no new App Store version.
// The numbers in this file are only offline fallbacks (and the Demo backend's values).
//
// Keys sent to the app: review_body_max_chars, review_max_tags, review_max_photos, review_media_auto_approve,
// submission_max_photos, media_max_bytes, filter_max_tags, filter_distance_min_m, filter_distance_max_m,
// filter_distance_step_m, filter_distance_default_m, filter_rating_step, visit_radius_m,
// visit_max_accuracy_m, visit_max_location_age_s.

import Foundation

/// Tunable app rules in one place. Verification thresholds here are only UX defaults —
/// the backend's `private.app_settings` is authoritative.
nonisolated struct AppConfiguration: Sendable {
    /// Delay before a typed query triggers a search.
    var searchDebounce: Duration = .milliseconds(350)
    /// Minimum characters before a text query hits the network.
    var minimumQueryLength = 2
    /// Page size for Explore results.
    var searchPageSize = 20
    /// Fallback map center when location is not available (Siam, Bangkok).
    var defaultCenter = GeoPoint(latitude: 13.7457, longitude: 100.5341)
    var verification = VerificationPolicy.default
    /// How long cached venue cards count as fresh before showing a "may be outdated" label.
    var venueCacheFreshness: TimeInterval = 15 * 60
    /// Cached cards older than this are not shown at all.
    var venueCacheMaxAge: TimeInterval = 7 * 24 * 60 * 60
    /// LRU caps applied by `LocalCache.prune` at launch (rows beyond these, least recently read first, are deleted).
    var venueCacheMaxEntries = 2_000
    var venueDetailCacheMaxEntries = 300
    var reviewMaxBodyLength = 500
    /// No practical limit: a reviewer may pick every tag in the catalog.
    var reviewMaxTags = ReviewTag.catalog.count
    var reviewMaxPhotos = 5
    /// Review photos are public right away and moderated afterwards.
    var reviewMediaAutoApprove = true
    var submissionMaxPhotos = 5
    var mediaMaxBytes = 5 * 1_024 * 1_024
    var filter = FilterLimits()
    var ranker = VenueRanker()
    /// Must match Supabase Auth → Email → "Email OTP Length" (supabase/config.toml `otp_length`).
    /// The sign-in screen auto-submits when this many digits are entered.
    static let emailOTPLength = 6

    static let standard = AppConfiguration()

    /// Explore filter ranges (distance slider and minimum-rating stars).
    nonisolated struct FilterLimits: Sendable, Equatable {
        var distanceMinMeters: Double = 500
        var distanceMaxMeters: Double = 20_000
        var distanceStepMeters: Double = 500
        var distanceDefaultMeters: Double = 3_000
        var ratingStep: Double = 0.5
        /// How many "Good for" (facility) chips may be combined. Default: all of them (no "pick up to 3").
        var maxTags = VenueFilter.goodForTags.count

        /// `nil` when every "Good for" chip can be selected at once.
        var tagSelectionLimit: Int? { maxTags >= VenueFilter.goodForTags.count ? nil : maxTags }

        /// Snaps a distance to the slider grid and keeps it inside the range.
        func snappedDistance(_ meters: Double) -> Double {
            let step = max(distanceStepMeters, 1)
            let snapped = distanceMinMeters + ((meters - distanceMinMeters) / step).rounded() * step
            return min(max(snapped, distanceMinMeters), distanceMaxMeters)
        }

        /// Snaps a rating to the step (e.g. 3.7 → 3.5 with 0.5 steps). `nil` or ≤ 0 means "any".
        func snappedRating(_ rating: Double?) -> Double? {
            guard let rating, rating > 0 else { return nil }
            let step = max(ratingStep, 0.1)
            return min(max((rating / step).rounded() * step, step), 5)
        }
    }

    /// Applies server values over these defaults. Missing or nonsensical values keep the default.
    func merged(with remote: RemoteConfigValues) -> AppConfiguration {
        var result = self
        func positive(_ value: Double?) -> Double? { value.flatMap { $0 > 0 && $0.isFinite ? $0 : nil } }
        func count(_ value: Double?) -> Int? { positive(value).map { Int($0.rounded()) } }

        if let value = count(remote.reviewBodyMaxChars) { result.reviewMaxBodyLength = value }
        if let value = count(remote.reviewMaxTags) { result.reviewMaxTags = value }
        if let value = count(remote.reviewMaxPhotos) { result.reviewMaxPhotos = min(value, 10) }
        if let value = remote.reviewMediaAutoApprove { result.reviewMediaAutoApprove = value }
        if let value = count(remote.submissionMaxPhotos) { result.submissionMaxPhotos = min(value, 10) }
        if let value = count(remote.mediaMaxBytes) { result.mediaMaxBytes = value }
        if let value = positive(remote.visitRadiusMeters) { result.verification.radiusMeters = value }
        if let value = positive(remote.visitMaxAccuracyMeters) { result.verification.maxHorizontalAccuracy = value }
        if let value = positive(remote.visitMaxLocationAgeSeconds) { result.verification.maxLocationAge = value }

        // Distance range is applied as a whole so min ≤ default ≤ max always holds.
        if let value = count(remote.filterMaxTags) { result.filter.maxTags = value }
        var filter = result.filter
        if let value = positive(remote.filterDistanceMinMeters) { filter.distanceMinMeters = value }
        if let value = positive(remote.filterDistanceMaxMeters) { filter.distanceMaxMeters = value }
        if let value = positive(remote.filterDistanceStepMeters) { filter.distanceStepMeters = value }
        if let value = positive(remote.filterDistanceDefaultMeters) { filter.distanceDefaultMeters = value }
        if let value = positive(remote.filterRatingStep), value <= 1 { filter.ratingStep = value }
        if filter.distanceMinMeters < filter.distanceMaxMeters {
            filter.distanceDefaultMeters = min(max(filter.distanceDefaultMeters, filter.distanceMinMeters), filter.distanceMaxMeters)
            result.filter = filter
        } else {
            result.filter.ratingStep = filter.ratingStep
        }
        return result
    }
}

/// `get_public_config()` payload. Every field is optional so an older or newer server never breaks the app.
nonisolated struct RemoteConfigValues: Codable, Hashable, Sendable {
    var reviewBodyMaxChars: Double?
    var reviewMaxTags: Double?
    var reviewMaxPhotos: Double?
    var reviewMediaAutoApprove: Bool?
    var submissionMaxPhotos: Double?
    var mediaMaxBytes: Double?
    var filterMaxTags: Double?
    var filterDistanceMinMeters: Double?
    var filterDistanceMaxMeters: Double?
    var filterDistanceStepMeters: Double?
    var filterDistanceDefaultMeters: Double?
    var filterRatingStep: Double?
    var visitRadiusMeters: Double?
    var visitMaxAccuracyMeters: Double?
    var visitMaxLocationAgeSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case reviewBodyMaxChars = "review_body_max_chars"
        case reviewMaxTags = "review_max_tags"
        case reviewMaxPhotos = "review_max_photos"
        case reviewMediaAutoApprove = "review_media_auto_approve"
        case submissionMaxPhotos = "submission_max_photos"
        case mediaMaxBytes = "media_max_bytes"
        case filterMaxTags = "filter_max_tags"
        case filterDistanceMinMeters = "filter_distance_min_m"
        case filterDistanceMaxMeters = "filter_distance_max_m"
        case filterDistanceStepMeters = "filter_distance_step_m"
        case filterDistanceDefaultMeters = "filter_distance_default_m"
        case filterRatingStep = "filter_rating_step"
        case visitRadiusMeters = "visit_radius_m"
        case visitMaxAccuracyMeters = "visit_max_accuracy_m"
        case visitMaxLocationAgeSeconds = "visit_max_location_age_s"
    }

    init(reviewBodyMaxChars: Double? = nil, reviewMaxTags: Double? = nil, reviewMaxPhotos: Double? = nil,
         reviewMediaAutoApprove: Bool? = nil, submissionMaxPhotos: Double? = nil, mediaMaxBytes: Double? = nil,
         filterMaxTags: Double? = nil, filterDistanceMinMeters: Double? = nil, filterDistanceMaxMeters: Double? = nil,
         filterDistanceStepMeters: Double? = nil, filterDistanceDefaultMeters: Double? = nil, filterRatingStep: Double? = nil,
         visitRadiusMeters: Double? = nil, visitMaxAccuracyMeters: Double? = nil, visitMaxLocationAgeSeconds: Double? = nil) {
        self.reviewBodyMaxChars = reviewBodyMaxChars
        self.reviewMaxTags = reviewMaxTags
        self.reviewMaxPhotos = reviewMaxPhotos
        self.reviewMediaAutoApprove = reviewMediaAutoApprove
        self.submissionMaxPhotos = submissionMaxPhotos
        self.mediaMaxBytes = mediaMaxBytes
        self.filterMaxTags = filterMaxTags
        self.filterDistanceMinMeters = filterDistanceMinMeters
        self.filterDistanceMaxMeters = filterDistanceMaxMeters
        self.filterDistanceStepMeters = filterDistanceStepMeters
        self.filterDistanceDefaultMeters = filterDistanceDefaultMeters
        self.filterRatingStep = filterRatingStep
        self.visitRadiusMeters = visitRadiusMeters
        self.visitMaxAccuracyMeters = visitMaxAccuracyMeters
        self.visitMaxLocationAgeSeconds = visitMaxLocationAgeSeconds
    }

    /// Tolerates numbers sent as strings or booleans sent as 0/1.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) -> Double? {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
            if let text = try? container.decodeIfPresent(String.self, forKey: key) { return Double(text) }
            return nil
        }
        reviewBodyMaxChars = number(.reviewBodyMaxChars)
        reviewMaxTags = number(.reviewMaxTags)
        reviewMaxPhotos = number(.reviewMaxPhotos)
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .reviewMediaAutoApprove) {
            reviewMediaAutoApprove = flag
        } else {
            reviewMediaAutoApprove = number(.reviewMediaAutoApprove).map { $0 == 1 }
        }
        submissionMaxPhotos = number(.submissionMaxPhotos)
        mediaMaxBytes = number(.mediaMaxBytes)
        filterMaxTags = number(.filterMaxTags)
        filterDistanceMinMeters = number(.filterDistanceMinMeters)
        filterDistanceMaxMeters = number(.filterDistanceMaxMeters)
        filterDistanceStepMeters = number(.filterDistanceStepMeters)
        filterDistanceDefaultMeters = number(.filterDistanceDefaultMeters)
        filterRatingStep = number(.filterRatingStep)
        visitRadiusMeters = number(.visitRadiusMeters)
        visitMaxAccuracyMeters = number(.visitMaxAccuracyMeters)
        visitMaxLocationAgeSeconds = number(.visitMaxLocationAgeSeconds)
    }
}
