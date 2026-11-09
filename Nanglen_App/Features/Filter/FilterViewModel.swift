import Foundation

/// Optional, secondary filters. Defaults are permissive.
final class FilterViewModel {
    private(set) var filter: VenueFilter
    var onChange: ((VenueFilter) -> Void)?

    init(filter: VenueFilter) {
        self.filter = filter
    }

    static let sorts = VenueFilter.Sort.allCases
    static let distances = VenueFilter.Distance.allCases
    static let ratings = VenueFilter.MinimumRating.allCases

    func setSort(index: Int) { update { $0.sort = Self.sorts[safe: index] ?? .relevance } }
    func setDistance(index: Int) { update { $0.distance = Self.distances[safe: index] ?? .km3 } }
    func setRating(index: Int) { update { $0.minimumRating = Self.ratings[safe: index] ?? .any } }
    func reset() { update { $0 = .default } }

    private func update(_ change: (inout VenueFilter) -> Void) {
        change(&filter)
        onChange?(filter)
    }

    static func title(for sort: VenueFilter.Sort) -> String {
        switch sort {
        case .relevance: L10n.Filter.sortRelevance
        case .distance: L10n.Filter.sortDistance
        case .rating: L10n.Filter.sortRating
        }
    }

    static func title(for distance: VenueFilter.Distance) -> String { Formatters.distance(distance.meters) }

    static func title(for rating: VenueFilter.MinimumRating) -> String {
        rating.value.map { "\(RatingSummary.format($0))+" } ?? L10n.Filter.any
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
