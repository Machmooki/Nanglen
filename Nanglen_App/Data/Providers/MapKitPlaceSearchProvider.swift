import Foundation
import MapKit

/// Apple MapKit local search. MapKit only knows names, addresses, categories
/// and contact info — crowd, noise, seats, Wi-Fi and outlets are never
/// inferred here; they come exclusively from local reports.
final class MapKitPlaceSearchProvider: PlaceSearchProvider {
    private struct CacheKey: Hashable {
        var kind: String
        var latitude: Int
        var longitude: Int
        var span: Int
    }

    private struct CacheEntry {
        var candidates: [PlaceCandidate]
        var storedAt: Date
    }

    private var cache: [CacheKey: CacheEntry] = [:]
    private let cacheLifetime: TimeInterval = 5 * 60

    func search(query: String, region: SearchRegion, categoryHint: VenueCategory?) async throws -> [PlaceCandidate] {
        let key = cacheKey("q:\(query.lowercased()):\(categoryHint?.rawValue ?? "-")", region: region)
        if let cached = cachedCandidates(for: key) { return cached }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region.mapKitRegion
        request.resultTypes = .pointOfInterest
        let response = try await MKLocalSearch(request: request).start()
        let candidates = Self.unique(response.mapItems.map { Self.candidate(from: $0, hint: categoryHint) })
        store(candidates, for: key)
        return candidates
    }

    func discover(category: VenueCategory?, region: SearchRegion) async throws -> [PlaceCandidate] {
        let key = cacheKey("d:\(category?.rawValue ?? "all")", region: region)
        if let cached = cachedCandidates(for: key) { return cached }

        let queries = Self.discoveryQueries(for: category)
        var collected: [PlaceCandidate] = []
        var lastError: Error?
        var anySucceeded = false
        // Run requests concurrently; tolerate partial failures.
        await withTaskGroup(of: Result<[PlaceCandidate], Error>.self) { group in
            for query in queries {
                group.addTask { await Self.run(query, region: region) }
            }
            for await result in group {
                switch result {
                case .success(let items):
                    anySucceeded = true
                    collected.append(contentsOf: items)
                case .failure(let error):
                    lastError = error
                }
            }
        }
        try Task.checkCancellation()
        if !anySucceeded, let lastError {
            // MKError.placemarkNotFound just means "nothing here".
            if (lastError as? MKError)?.code == .placemarkNotFound { return [] }
            throw lastError
        }
        let candidates = Self.unique(collected)
        store(candidates, for: key)
        return candidates
    }

    // MARK: Discovery plan

    /// Sendable description of one MapKit request.
    nonisolated enum DiscoveryQuery: Sendable, Hashable {
        case pointsOfInterest([String])
        case text(String, hint: VenueCategory)

        var hint: VenueCategory? {
            if case .text(_, let hint) = self { return hint }
            return nil
        }
    }

    static func discoveryQueries(for category: VenueCategory?) -> [DiscoveryQuery] {
        let cafe = MKPointOfInterestCategory.cafe.rawValue
        let library = MKPointOfInterestCategory.library.rawValue
        let university = MKPointOfInterestCategory.university.rawValue
        switch category {
        case .cafe:
            return [.pointsOfInterest([cafe])]
        case .library:
            return [.pointsOfInterest([library]), .text("ห้องสมุด", hint: .library)]
        case .coworking:
            return [.text("co-working space", hint: .coworking), .text("โคเวิร์กกิ้งสเปซ", hint: .coworking)]
        case .studySpace:
            return [.text("study space", hint: .studySpace), .text("ที่อ่านหนังสือ", hint: .studySpace), .pointsOfInterest([university])]
        case .other, .none:
            return [.pointsOfInterest([cafe, library, university]), .text("co-working space", hint: .coworking)]
        }
    }

    static func run(_ query: DiscoveryQuery, region: SearchRegion) async -> Result<[PlaceCandidate], Error> {
        do {
            let response = try await makeSearch(query, region: region).start()
            return .success(response.mapItems.map { candidate(from: $0, hint: query.hint) })
        } catch {
            return .failure(error)
        }
    }

    static func makeSearch(_ query: DiscoveryQuery, region: SearchRegion) -> MKLocalSearch {
        switch query {
        case .pointsOfInterest(let rawCategories):
            let request = MKLocalPointsOfInterestRequest(coordinateRegion: region.mapKitRegion)
            let categories = rawCategories.map { MKPointOfInterestCategory(rawValue: $0) }
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
            return MKLocalSearch(request: request)
        case .text(let text, _):
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = region.mapKitRegion
            request.resultTypes = .pointOfInterest
            return MKLocalSearch(request: request)
        }
    }

    // MARK: Mapping

    static func candidate(from item: MKMapItem, hint: VenueCategory?) -> PlaceCandidate {
        let location = item.location.coordinate
        let name = item.name ?? L10n.Common.unnamedPlace
        let identifier = item.identifier?.rawValue
            ?? PlaceCandidate.fallbackIdentifier(name: name, latitude: location.latitude, longitude: location.longitude)
        let address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? item.address?.shortAddress
            ?? item.address?.fullAddress
        return PlaceCandidate(
            externalPlaceID: identifier,
            name: name,
            address: address,
            latitude: location.latitude,
            longitude: location.longitude,
            category: CategoryClassifier.classify(
                name: name,
                pointOfInterestCategory: item.pointOfInterestCategory?.rawValue,
                hint: hint
            ),
            phoneNumber: item.phoneNumber,
            websiteURL: item.url?.absoluteString
        )
    }

    static func unique(_ candidates: [PlaceCandidate]) -> [PlaceCandidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.externalPlaceID).inserted }
    }

    // MARK: Cache

    private func cacheKey(_ kind: String, region: SearchRegion) -> CacheKey {
        CacheKey(
            kind: kind,
            latitude: Int((region.center.latitude * 500).rounded()),
            longitude: Int((region.center.longitude * 500).rounded()),
            span: Int((region.latitudeDelta * 100).rounded())
        )
    }

    private func cachedCandidates(for key: CacheKey) -> [PlaceCandidate]? {
        guard let entry = cache[key], Date().timeIntervalSince(entry.storedAt) < cacheLifetime else { return nil }
        return entry.candidates
    }

    private func store(_ candidates: [PlaceCandidate], for key: CacheKey) {
        if cache.count > 40 { cache.removeAll() }
        cache[key] = CacheEntry(candidates: candidates, storedAt: Date())
    }
}

extension SearchRegion {
    var mapKitRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    init(_ region: MKCoordinateRegion) {
        self.init(
            center: GeoPoint(latitude: region.center.latitude, longitude: region.center.longitude),
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta
        )
    }
}
