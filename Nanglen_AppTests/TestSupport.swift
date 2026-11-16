import Foundation
import Testing
@testable import Nanglen_App

/// Deterministic fixtures — no live GPS, no live MapKit, no network.
enum Fixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Demo seed venue 1 (Baicha Café) and its coordinate.
    static let cafeID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let cafe = GeoPoint(latitude: 13.7462, longitude: 100.5326)
    static let libraryID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    static func reading(_ point: GeoPoint = cafe, accuracy: Double = 10, age: TimeInterval = 2) -> LocationReading {
        LocationReading(point: point, horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(-age))
    }

    /// ~meters north of a point.
    static func north(of point: GeoPoint, meters: Double) -> GeoPoint {
        GeoPoint(latitude: point.latitude + meters / 111_195, longitude: point.longitude)
    }

    static func summary(id: UUID = UUID(), name: String = "Test", average: Double?, count: Int, distance: Double? = nil) -> VenueSummary {
        VenueSummary(id: id, name: name, category: .cafe, address: nil, coordinate: cafe, status: .active,
                     rating: RatingSummary(reviewCount: count, average: average), topTags: [], coverPath: nil,
                     distanceMeters: distance, rankScore: nil)
    }
}

/// Mutable clock for time-based rules (challenge expiry, verification expiry).
@MainActor
final class TestClock {
    var now = Fixtures.now
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Demo backend wired to a test clock, in memory, with demo seed data.
@MainActor
func makeBackend(clock: TestClock = TestClock()) -> DemoBackend {
    DemoBackend(directory: nil, seed: true, clock: { clock.now })
}

/// Signs in a new Guest and verifies an email (Registered), or resumes that user if it exists.
@MainActor
func registerUser(_ backend: DemoBackend, email: String = "one@example.test") async throws {
    if backend.resumeSessionForTesting(email: email) { return }
    try await backend.signOut() // fresh anonymous session
    try await backend.requestEmailLink(email: email)
    try await backend.confirmEmailLink(email: email, code: DemoSeed.demoOTP)
}

/// Mock location provider with scripted readings.
@MainActor
final class MockLocation: LocationProviding {
    var authorization: LocationAuthorization
    var readings: [Result<LocationReading, Error>]
    private(set) var lastKnownLocation: LocationReading?
    private(set) var authorizationRequests = 0

    init(authorization: LocationAuthorization = .authorized, readings: [Result<LocationReading, Error>]) {
        self.authorization = authorization
        self.readings = readings
    }

    func requestAuthorization() async -> LocationAuthorization {
        authorizationRequests += 1
        if authorization == .notDetermined { authorization = .authorized }
        return authorization
    }

    func requestCurrentLocation() async throws -> LocationReading {
        guard authorization == .authorized else { throw LocationError.notAuthorized }
        let next = readings.isEmpty ? .failure(LocationError.timedOut) : readings.removeFirst()
        let reading = try next.get()
        lastKnownLocation = reading
        return reading
    }
}

extension BackendError {
    static func matches(_ expected: BackendError) -> (Error) -> Bool {
        { ($0 as? BackendError) == expected }
    }
}
