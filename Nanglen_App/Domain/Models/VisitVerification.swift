import Foundation

/// Tunable thresholds (Product Rules §5). Starting values only; the server's copy is authoritative.
nonisolated struct VerificationPolicy: Hashable, Sendable {
    var radiusMeters: Double = 100
    var maxHorizontalAccuracy: Double = 50
    var maxLocationAge: TimeInterval = 60

    static let `default` = VerificationPolicy()
}

/// One Core Location reading, framework-free. Exact coordinates are sent once to the
/// verification endpoint and never stored by the app.
nonisolated struct LocationReading: Hashable, Sendable {
    var point: GeoPoint
    var horizontalAccuracy: Double
    var timestamp: Date
}

/// A short-lived, one-time server challenge bound to (user, venue).
nonisolated struct VisitChallenge: Hashable, Sendable {
    var id: UUID
    var venueID: UUID
    var issuedAt: Date
    var expiresAt: Date
    var policy: VerificationPolicy
}

/// Server outcome of evaluating one reading against one challenge.
nonisolated enum VisitVerificationStatus: String, Codable, Hashable, Sendable {
    case verified
    case tooFar = "too_far"
    case inaccurate
    case stale
    case invalid
}

nonisolated struct VisitVerificationResult: Hashable, Sendable {
    var status: VisitVerificationStatus
    /// Present only when `status == .verified`. One-time; consumed by `submit_review`.
    var verificationID: UUID?
    var expiresAt: Date?
    var distanceBucket: String?
}

/// Client-side UX pre-check. Never authoritative: the server decides.
nonisolated enum ReadingPreCheck: Hashable, Sendable {
    case plausible(distance: Double)
    case tooFar(distance: Double)
    case inaccurate(accuracy: Double)
    case stale(age: TimeInterval)
    case invalid
}

nonisolated enum VisitReadingEvaluator {
    static func evaluate(_ reading: LocationReading, venue: GeoPoint, policy: VerificationPolicy, now: Date) -> ReadingPreCheck {
        guard reading.point.isValid, reading.horizontalAccuracy >= 0 else { return .invalid }
        let age = now.timeIntervalSince(reading.timestamp)
        if age > policy.maxLocationAge { return .stale(age: age) }
        if reading.horizontalAccuracy > policy.maxHorizontalAccuracy { return .inaccurate(accuracy: reading.horizontalAccuracy) }
        let distance = reading.point.distance(to: venue)
        if distance > policy.radiusMeters { return .tooFar(distance: distance) }
        return .plausible(distance: distance)
    }
}
