import Foundation

/// External place discovery. MapKit today; any other source can conform.
protocol PlaceSearchProvider: AnyObject {
    /// Free-text search ("cafe", "TK Park") around a region.
    func search(query: String, region: SearchRegion, categoryHint: VenueCategory?) async throws -> [PlaceCandidate]
    /// Browse study/work-friendly places in a region, optionally one category.
    func discover(category: VenueCategory?, region: SearchRegion) async throws -> [PlaceCandidate]
}

nonisolated enum PlaceSearchError: Error, Sendable {
    case noResults
    case unavailable(String)
}
