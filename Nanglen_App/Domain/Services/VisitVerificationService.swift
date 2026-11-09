import Foundation

/// UI-facing states of the location-verified visit flow.
nonisolated enum VerificationState: Hashable, Sendable {
    case idle
    case requestingPermission
    case checkingLocation
    case verifying
    case verified(verificationID: UUID, expiresAt: Date?)
    case tooFar(distanceMeters: Double?)
    case inaccurate(accuracyMeters: Double?)
    case stale
    case unavailable
    case permissionDenied
    case registrationRequired
    case failed(String)

    var isTerminalFailure: Bool {
        switch self {
        case .tooFar, .inaccurate, .stale, .unavailable, .permissionDenied, .failed: true
        default: false
        }
    }

    var verificationID: UUID? {
        if case .verified(let id, _) = self { return id }
        return nil
    }
}

/// Orchestrates: permission (asked only now) → one-time server challenge → fresh Core Location
/// reading → server verification. The client never decides "verified"; it only relays the
/// server's one-time verification id. GPS data is a best-effort signal and can be spoofed.
final class VisitVerificationService {
    private let reviews: ReviewRepository
    private let location: LocationProviding
    private let clock: () -> Date
    /// Extra readings requested while GPS warms up indoors.
    private let maxReadingAttempts: Int

    init(reviews: ReviewRepository, location: LocationProviding, clock: @escaping () -> Date = { Date() }, maxReadingAttempts: Int = 3) {
        self.reviews = reviews
        self.location = location
        self.clock = clock
        self.maxReadingAttempts = maxReadingAttempts
    }

    func verify(venue: VenueSummary, onChange: (VerificationState) -> Void) async -> VerificationState {
        // 1. Permission — requested at this moment, never at launch.
        if location.authorization == .notDetermined {
            onChange(.requestingPermission)
            _ = await location.requestAuthorization()
        }
        switch location.authorization {
        case .denied, .restricted: return finish(.permissionDenied, onChange)
        default: break
        }

        // 2. One-time challenge bound to (user, venue).
        onChange(.checkingLocation)
        let challenge: VisitChallenge
        do {
            challenge = try await reviews.issueChallenge(venueID: venue.id)
        } catch BackendError.registrationRequired {
            return finish(.registrationRequired, onChange)
        } catch {
            return finish(.failed(Self.message(for: error)), onChange)
        }

        // 3. Fresh reading taken after the challenge was issued; retry while accuracy improves.
        var best: LocationReading?
        for attempt in 0..<maxReadingAttempts {
            do {
                let reading = try await location.requestCurrentLocation()
                if best == nil || reading.horizontalAccuracy < (best?.horizontalAccuracy ?? .infinity) { best = reading }
                let check = VisitReadingEvaluator.evaluate(reading, venue: venue.coordinate, policy: challenge.policy, now: clock())
                if case .inaccurate = check, attempt < maxReadingAttempts - 1 { continue }
                if case .stale = check, attempt < maxReadingAttempts - 1 { continue }
                if case .invalid = check, attempt < maxReadingAttempts - 1 { continue }
                break
            } catch LocationError.notAuthorized {
                return finish(.permissionDenied, onChange)
            } catch {
                if attempt == maxReadingAttempts - 1 && best == nil { return finish(.unavailable, onChange) }
            }
        }
        guard let reading = best else { return finish(.unavailable, onChange) }

        // 4. Server decides. The challenge is consumed by this single attempt.
        onChange(.verifying)
        do {
            let result = try await reviews.verify(challengeID: challenge.id, reading: reading)
            switch result.status {
            case .verified:
                guard let id = result.verificationID else { return finish(.failed("missing_verification"), onChange) }
                return finish(.verified(verificationID: id, expiresAt: result.expiresAt), onChange)
            case .tooFar:
                return finish(.tooFar(distanceMeters: reading.point.distance(to: venue.coordinate)), onChange)
            case .inaccurate:
                return finish(.inaccurate(accuracyMeters: reading.horizontalAccuracy), onChange)
            case .stale:
                return finish(.stale, onChange)
            case .invalid:
                return finish(.unavailable, onChange)
            }
        } catch {
            return finish(.failed(Self.message(for: error)), onChange)
        }
    }

    private func finish(_ state: VerificationState, _ onChange: (VerificationState) -> Void) -> VerificationState {
        onChange(state)
        return state
    }

    static func message(for error: Error) -> String {
        (error as? BackendError).map(L10n.Errors.message(for:)) ?? L10n.Common.somethingWentWrong
    }
}
