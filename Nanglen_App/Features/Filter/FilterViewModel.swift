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
    func setTags(_ tags: Set<String>) { update { $0.tags = Set(tags.prefix(VenueFilter.maxTags)) } }
    func setReviewedOnly(_ on: Bool) { update { $0.reviewedOnly = on } }

    /// Short label for an active filter chip on Explore.
    static func title(for item: VenueFilter.Item, in filter: VenueFilter) -> String {
        switch item {
        case .tag(let slug): ReviewTag.title(for: slug)
        case .minimumRating: L10n.Filter.ratingAtLeast(filter.minimumRating.value.map(RatingSummary.format) ?? "")
        case .reviewedOnly: L10n.Filter.hasReviews
        case .distance: L10n.Filter.within(title(for: filter.distance))
        case .sort: title(for: filter.sort)
        }
    }

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
