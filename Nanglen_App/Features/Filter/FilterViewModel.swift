import Foundation

/// Optional, secondary filters. Defaults are permissive. Ranges and defaults come from the server config.
final class FilterViewModel {
    private(set) var filter: VenueFilter
    let limits: AppConfiguration.FilterLimits
    var onChange: ((VenueFilter) -> Void)?

    init(filter: VenueFilter, limits: AppConfiguration.FilterLimits = AppConfiguration.FilterLimits()) {
        self.limits = limits
        var filter = filter
        filter.distanceMeters = limits.snappedDistance(filter.distanceMeters)
        filter.minimumRating = limits.snappedRating(filter.minimumRating)
        self.filter = filter
    }

    static let sorts = VenueFilter.Sort.allCases

    func setSort(index: Int) { update { $0.sort = Self.sorts[safe: index] ?? .relevance } }

    /// Slider value while dragging or after release; always snapped to the configured step.
    func setDistance(_ meters: Double) {
        let snapped = limits.snappedDistance(meters)
        guard snapped != filter.distanceMeters else { return }
        update { $0.distanceMeters = snapped }
    }

    /// `nil` (or 0) = any rating.
    func setMinimumRating(_ rating: Double?) {
        let snapped = limits.snappedRating(rating)
        guard snapped != filter.minimumRating else { return }
        update { $0.minimumRating = snapped }
    }

    func reset() {
        update { $0 = VenueFilter(limits: limits) }
    }

    func setTags(_ tags: Set<String>) { update { $0.tags = Set(tags.prefix(limits.maxTags)) } }
    func setReviewedOnly(_ on: Bool) { update { $0.reviewedOnly = on } }

    /// Short label for an active filter chip on Explore.
    static func title(for item: VenueFilter.Item, in filter: VenueFilter) -> String {
        switch item {
        case .tag(let slug): ReviewTag.title(for: slug)
        case .minimumRating: L10n.Filter.ratingAtLeast(filter.minimumRating.map(RatingSummary.format) ?? "")
        case .reviewedOnly: L10n.Filter.hasReviews
        case .distance: L10n.Filter.within(distanceText(filter.distanceMeters))
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

    /// "750 m", "2.5 km", "12 km", "12.5 km" (keeps the half step visible above 10 km).
    static func distanceText(_ meters: Double) -> String {
        guard meters >= 1_000 else { return Formatters.distance(meters) }
        let km = (meters / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(Formatters.appLocale))
        return String(localized: "\(km) km")
    }

    /// "4.0 stars & up" or "Any rating".
    static func ratingText(_ rating: Double?) -> String {
        rating.map { L10n.Filter.ratingAtLeastLong(RatingSummary.format($0)) } ?? L10n.Filter.anyRating
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
