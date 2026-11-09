import CoreLocation
import Foundation

enum LocationAuthorization: Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

nonisolated enum LocationError: Error, Sendable {
    case notAuthorized
    case timedOut
    case failed(String)
}

/// What features need from location. Mockable for tests and previews.
protocol LocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    var lastKnownLocation: LocationReading? { get }
    /// Asks for When-In-Use permission (only prompts if not determined yet).
    func requestAuthorization() async -> LocationAuthorization
    /// One-shot fix with timestamp and horizontal accuracy. Never starts continuous tracking.
    func requestCurrentLocation() async throws -> LocationReading
}

/// Thin wrapper over CLLocationManager: When-In-Use only, one-shot requests,
/// no background or continuous tracking.
final class LocationManager: NSObject, LocationProviding {
    private let manager = CLLocationManager()
    private var authorizationContinuations: [CheckedContinuation<LocationAuthorization, Never>] = []
    private var locationContinuations: [CheckedContinuation<LocationReading, Error>] = []
    private var timeoutTask: Task<Void, Never>?
    private(set) var lastKnownLocation: LocationReading?

    /// Called whenever authorization changes (e.g. from Settings).
    var onAuthorizationChange: ((LocationAuthorization) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var authorization: LocationAuthorization {
        Self.map(manager.authorizationStatus)
    }

    func requestAuthorization() async -> LocationAuthorization {
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestCurrentLocation() async throws -> LocationReading {
        var status = authorization
        if status == .notDetermined { status = await requestAuthorization() }
        guard status == .authorized else { throw LocationError.notAuthorized }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuations.append(continuation)
            guard locationContinuations.count == 1 else { return }
            manager.requestLocation()
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.finishLocationRequests(with: .failure(LocationError.timedOut))
            }
        }
    }

    private func finishLocationRequests(with result: Result<LocationReading, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuations = locationContinuations
        locationContinuations.removeAll()
        continuations.forEach { $0.resume(with: result) }
    }

    private func handleAuthorizationChange() {
        let status = authorization
        guard status != .notDetermined else { return }
        let continuations = authorizationContinuations
        authorizationContinuations.removeAll()
        continuations.forEach { $0.resume(returning: status) }
        if status != .authorized, !locationContinuations.isEmpty {
            finishLocationRequests(with: .failure(LocationError.notAuthorized))
        }
        onAuthorizationChange?(status)
    }

    private func handle(location: CLLocation) {
        let sample = LocationReading(
            point: GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        lastKnownLocation = sample
        finishLocationRequests(with: .success(sample))
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .denied
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    // CLLocationManager delivers callbacks on the thread it was created on (main).
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { handleAuthorizationChange() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated { handle(location: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            finishLocationRequests(with: .failure(LocationError.failed(message)))
        }
    }
}
