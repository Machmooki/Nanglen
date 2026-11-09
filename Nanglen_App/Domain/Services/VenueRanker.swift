import Foundation

/// Discovery ranking, mirroring `public.search_venues`:
///
///     bayes      = (C·m + Σratings) / (C + n)          (confidence-aware rating)
///     quality    = (bayes − 1) / 4                      ∈ [0, 1]
///     proximity  = 1 / (1 + distance_km)                (0.5 when no origin)
///     score      = 0.50·relevance + 0.25·quality + 0.25·proximity   (text query)
///                = 0.55·quality + 0.45·proximity                    (browsing)
///
/// The plain average is what users see; `bayes` only orders results so one 5★ review
/// does not outrank many strong reviews. Paid/business status never enters the score.
nonisolated struct VenueRanker: Sendable {
    var priorMean: Double = 3.5
    var priorWeight: Double = 5

    func bayesianRating(average: Double?, count: Int) -> Double {
        let sum = (average ?? 0) * Double(count)
        return (priorWeight * priorMean + sum) / (priorWeight + Double(count))
    }

    func proximity(distanceMeters: Double?) -> Double {
        guard let distanceMeters else { return 0.5 }
        return 1 / (1 + distanceMeters / 1_000)
    }

    /// Text relevance in [0, 1]: prefix > substring > token overlap.
    func relevance(name: String, query: String) -> Double {
        let n = Self.normalize(name)
        let q = Self.normalize(query)
        guard !q.isEmpty else { return 0 }
        if n.hasPrefix(q) { return 0.9 }
        if n.contains(q) { return 0.7 }
        let nameTokens = Set(n.split(separator: " "))
        let queryTokens = q.split(separator: " ")
        let matched = queryTokens.filter { token in nameTokens.contains { $0.hasPrefix(token) } }.count
        return queryTokens.isEmpty ? 0 : 0.6 * Double(matched) / Double(queryTokens.count)
    }

    func score(rating: RatingSummary, distanceMeters: Double?, relevance: Double?) -> Double {
        let quality = (bayesianRating(average: rating.average, count: rating.reviewCount) - 1) / 4
        let near = proximity(distanceMeters: distanceMeters)
        if let relevance {
            return 0.50 * relevance + 0.25 * quality + 0.25 * near
        }
        return 0.55 * quality + 0.45 * near
    }

    func sort(_ venues: [VenueSummary], by sort: VenueFilter.Sort) -> [VenueSummary] {
        venues.sorted { lhs, rhs in
            switch sort {
            case .relevance:
                if (lhs.rankScore ?? 0) != (rhs.rankScore ?? 0) { return (lhs.rankScore ?? 0) > (rhs.rankScore ?? 0) }
            case .distance:
                if lhs.distanceMeters != rhs.distanceMeters {
                    return (lhs.distanceMeters ?? .greatestFiniteMagnitude) < (rhs.distanceMeters ?? .greatestFiniteMagnitude)
                }
            case .rating:
                let l = bayesianRating(average: lhs.rating.average, count: lhs.rating.reviewCount)
                let r = bayesianRating(average: rhs.rating.average, count: rhs.rating.reviewCount)
                if l != r { return l > r }
                if lhs.rating.reviewCount != rhs.rating.reviewCount { return lhs.rating.reviewCount > rhs.rating.reviewCount }
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
