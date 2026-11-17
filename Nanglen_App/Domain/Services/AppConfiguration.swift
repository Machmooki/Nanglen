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
    var reviewMaxBodyLength = 500
    var reviewMaxTags = 3
    var reviewMaxPhotos = 3
    var submissionMaxPhotos = 5
    var mediaMaxBytes = 5 * 1_024 * 1_024
    var ranker = VenueRanker()
    /// Must match Supabase Auth → Email → "Email OTP Length" (supabase/config.toml `otp_length`).
    /// The sign-in screen auto-submits when this many digits are entered.
    static let emailOTPLength = 6

    static let standard = AppConfiguration()
}
