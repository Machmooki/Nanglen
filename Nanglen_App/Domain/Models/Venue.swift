import Foundation

/// Kind of place (controlled vocabulary shared with the backend enum `venue_category`).
nonisolated enum VenueCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case cafe
    case library
    case coworking
    case studySpace = "study_space"
    case other
}

/// Publication/operational status of a canonical venue.
nonisolated enum VenueStatus: String, Codable, Hashable, Sendable {
    case active
    case temporarilyClosed = "temporarily_closed"
    case permanentlyClosed = "permanently_closed"
    case archived

    var acceptsReviews: Bool { self == .active || self == .temporarilyClosed }
}

/// A latitude/longitude pair with no framework dependency, so domain logic
/// stays testable without CoreLocation.
nonisolated struct GeoPoint: Hashable, Sendable, Codable {
    var latitude: Double
    var longitude: Double

    var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }

    /// Great-circle distance in meters (haversine).
    func distance(to other: GeoPoint) -> Double {
        let earthRadius = 6_371_008.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// The area a search runs in (usually the visible map region).
nonisolated struct SearchRegion: Hashable, Sendable {
    var center: GeoPoint
    var latitudeDelta: Double
    var longitudeDelta: Double

    /// Approximate radius covering the region, used for server-side radius filtering.
    var radiusMeters: Double {
        let corner = GeoPoint(latitude: center.latitude + latitudeDelta / 2, longitude: center.longitude + longitudeDelta / 2)
        return max(300, center.distance(to: corner))
    }

    /// Region centred on a point with a radius in meters.
    static func around(_ center: GeoPoint, radiusMeters: Double) -> SearchRegion {
        let latDelta = (radiusMeters * 2) / 111_000
        let lonDelta = (radiusMeters * 2) / max(111_000 * cos(center.latitude * .pi / 180), 1)
        return SearchRegion(center: center, latitudeDelta: latDelta, longitudeDelta: lonDelta)
    }
}

/// Plain average + count shown to people. `average` is nil when there are no reviews —
/// the UI then says "No reviews yet" instead of 0.0.
nonisolated struct RatingSummary: Hashable, Sendable, Codable {
    var reviewCount: Int
    var average: Double?

    static let empty = RatingSummary(reviewCount: 0, average: nil)

    var hasReviews: Bool { reviewCount > 0 && average != nil }
}

/// Compact approved-venue card used by Explore, Saved and the map.
/// Never contains full review history (fetched only on Venue Detail).
nonisolated struct VenueSummary: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var name: String
    var category: VenueCategory
    var address: String?
    var coordinate: GeoPoint
    var status: VenueStatus
    var rating: RatingSummary
    /// Up to three most-selected community tag slugs (user impressions, not facts).
    var topTags: [String]
    var coverPath: String?
    /// Server-computed distance from the search origin, if one was given.
    var distanceMeters: Double?
    /// Server/ranker score for "relevance" ordering; not displayed.
    var rankScore: Double?
}

/// Full detail for one approved venue.
nonisolated struct VenueDetail: Hashable, Sendable {
    var summary: VenueSummary
    var description: String?
    /// Official details are present only when their source is known.
    var websiteURL: URL?
    var phoneNumber: String?
    var detailsSource: String?
    var appleMapsID: String?
    /// Counts for 1…5 stars (index 0 = 1 star). Nil when there are no reviews.
    var ratingDistribution: [Int]?
    var lastReviewAt: Date?
    var tagCounts: [TagCount]
    var photoPaths: [String]
    var isFavorite: Bool
    var isManagedByMe: Bool
    var myReview: MyReview?
    /// Storage path of an equirectangular (2:1) 360° photo of the place, when the team or owner added one.
    var panoramaPath: String? = nil

    var id: UUID { summary.id }
}

nonisolated struct TagCount: Hashable, Sendable, Codable {
    var slug: String
    var count: Int
}

/// A place returned by Apple MapKit. It is only a *candidate*: it never becomes a
/// Nanglen venue without an Admin-approved submission.
nonisolated struct PlaceCandidate: Hashable, Sendable {
    var externalPlaceID: String
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var category: VenueCategory
    var phoneNumber: String?
    var websiteURL: String?

    var coordinate: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
    /// True when MapKit gave a real Apple Maps identifier (usable as a provider reference).
    var hasProviderIdentifier: Bool { !externalPlaceID.hasPrefix("geo:") }

    /// Stable identifier used when the provider has no identifier of its own:
    /// normalized name + coordinate rounded to ~11 m.
    static func fallbackIdentifier(name: String, latitude: Double, longitude: Double) -> String {
        let normalized = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return String(format: "geo:%@:%.4f,%.4f", normalized, latitude, longitude)
    }
}

/// What the user asked Explore for. Filters stay optional and permissive.
nonisolated struct VenueSearchQuery: Hashable, Sendable {
    var text: String = ""
    var origin: GeoPoint?
    var radiusMeters: Double = 3_000
    var category: VenueCategory?
    var filter: VenueFilter = .default
    var limit: Int = 20
    var offset: Int = 0

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

nonisolated struct VenueFilter: Hashable, Sendable {
    enum Sort: String, CaseIterable, Hashable, Sendable {
        case relevance, distance, rating
    }

    var sort: Sort = .relevance
    /// Search radius in meters (slider; range and default come from the server config).
    var distanceMeters: Double
    /// The default this filter was created with, so "active" and "remove" don't need the config.
    var defaultDistanceMeters: Double
    /// Minimum average rating, `nil` = any. Steps come from the server config (e.g. 0.5).
    var minimumRating: Double?
    /// "Good for" community tags; a venue must have each tag chosen by visitors.
    var tags: Set<String> = []
    var reviewedOnly = false

    init(defaultDistanceMeters: Double = 3_000) {
        self.defaultDistanceMeters = defaultDistanceMeters
        distanceMeters = defaultDistanceMeters
    }

    /// Default filter for the current server limits.
    init(limits: AppConfiguration.FilterLimits) {
        self.init(defaultDistanceMeters: limits.distanceDefaultMeters)
    }

    static let `default` = VenueFilter()
    /// Tags offered as filters (positive "good for" impressions; "expensive" is not a filter).
    static let goodForTags = ["study_friendly", "work_friendly", "quiet", "good_wifi", "power_outlets",
                              "comfortable_seating", "good_lighting", "good_value", "lively"]

    var isDistanceDefault: Bool { abs(distanceMeters - defaultDistanceMeters) < 1 }

    /// Number of non-default choices, shown as a badge on the filter button.
    var activeCount: Int {
        tags.count + [sort != .relevance, !isDistanceDefault, minimumRating != nil, reviewedOnly].filter { $0 }.count
    }

    /// Active choices in display order, for removable summary chips.
    enum Item: Hashable, Sendable {
        case tag(String), minimumRating, reviewedOnly, distance, sort
    }

    var activeItems: [Item] {
        var items: [Item] = tags.sorted { (Self.goodForTags.firstIndex(of: $0) ?? 99) < (Self.goodForTags.firstIndex(of: $1) ?? 99) }.map(Item.tag)
        if minimumRating != nil { items.append(.minimumRating) }
        if reviewedOnly { items.append(.reviewedOnly) }
        if !isDistanceDefault { items.append(.distance) }
        if sort != .relevance { items.append(.sort) }
        return items
    }

    mutating func remove(_ item: Item) {
        switch item {
        case .tag(let slug): tags.remove(slug)
        case .minimumRating: minimumRating = nil
        case .reviewedOnly: reviewedOnly = false
        case .distance: distanceMeters = defaultDistanceMeters
        case .sort: sort = .relevance
        }
    }

    /// Everything back to defaults, keeping the configured default distance.
    mutating func reset() {
        self = VenueFilter(defaultDistanceMeters: defaultDistanceMeters)
    }

    /// Local check used for cached/offline results (server applies the authoritative filter).
    func matches(_ venue: VenueSummary) -> Bool {
        if let minimum = minimumRating, (venue.rating.average ?? 0) < minimum { return false }
        if reviewedOnly, !venue.rating.hasReviews { return false }
        return tags.allSatisfy(venue.topTags.contains)
    }
}

nonisolated struct VenueSearchPage: Hashable, Sendable {
    var venues: [VenueSummary]
    var hasMore: Bool
}
