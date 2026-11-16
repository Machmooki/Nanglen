import UIKit

// Display mapping for domain values (titles, SF Symbols, tones) so wording stays consistent.

extension VenueCategory {
    var title: String {
        switch self {
        case .cafe: L10n.Category.cafe
        case .library: L10n.Category.library
        case .coworking: L10n.Category.coworking
        case .studySpace: L10n.Category.studySpace
        case .other: L10n.Category.other
        }
    }

    var symbol: String {
        switch self {
        case .cafe: "cup.and.saucer.fill"
        case .library: "books.vertical.fill"
        case .coworking: "laptopcomputer"
        case .studySpace: "graduationcap.fill"
        case .other: "mappin.and.ellipse"
        }
    }
}

extension RatingSummary {
    /// "4.6 · 28 reviews" or "No reviews yet" — never "0.0".
    var displayText: String {
        guard hasReviews, let average else { return L10n.Rating.noReviews }
        return L10n.Rating.summary(Self.format(average), reviewCount)
    }

    var accessibilityText: String {
        guard hasReviews, let average else { return L10n.Rating.noReviews }
        return L10n.Rating.accessibility(Self.format(average), reviewCount)
    }

    static func format(_ average: Double) -> String {
        average.formatted(.number.precision(.fractionLength(1)).locale(Formatters.appLocale))
    }
}

extension ReviewTag {
    var title: String {
        Formatters.appLocale.language.languageCode?.identifier == "en" ? labelEN : labelTH
    }

    var symbol: String {
        switch slug {
        case "study_friendly": "book.fill"
        case "work_friendly": "laptopcomputer"
        case "quiet": "speaker.slash.fill"
        case "lively": "music.note"
        case "good_lighting": "sun.max.fill"
        case "good_wifi": "wifi"
        case "power_outlets": "powerplug.fill"
        case "comfortable_seating": "sofa.fill"
        case "good_value": "hand.thumbsup.fill"
        case "expensive": "banknote"
        default: "tag.fill"
        }
    }

    static func title(for slug: String) -> String { named(slug)?.title ?? slug }

    static func pill(for slug: String, count: Int? = nil) -> StatusPillModel {
        let tag = named(slug)
        let text = count.map { "\(tag?.title ?? slug) · \($0)" } ?? (tag?.title ?? slug)
        return StatusPillModel(symbol: tag?.symbol ?? "tag.fill", text: text, tone: .brand, accessibilityLabel: text)
    }
}

extension VisitPurpose {
    var title: String {
        switch self {
        case .study: L10n.Purpose.study
        case .work: L10n.Purpose.work
        case .meeting: L10n.Purpose.meeting
        case .relax: L10n.Purpose.relax
        case .other: L10n.Purpose.other
        }
    }

    var symbol: String {
        switch self {
        case .study: "book"
        case .work: "laptopcomputer"
        case .meeting: "person.2"
        case .relax: "cup.and.saucer"
        case .other: "ellipsis.circle"
        }
    }
}

extension SubmissionStatus {
    var title: String {
        switch self {
        case .draft: L10n.SubmissionStatusText.draft
        case .pendingReview: L10n.SubmissionStatusText.pending
        case .needsChanges: L10n.SubmissionStatusText.needsChanges
        case .approved: L10n.SubmissionStatusText.approved
        case .rejected: L10n.SubmissionStatusText.rejected
        case .duplicate: L10n.SubmissionStatusText.duplicate
        case .withdrawn: L10n.SubmissionStatusText.withdrawn
        }
    }

    var tone: StatusTone {
        switch self {
        case .approved: .good
        case .pendingReview, .draft: .brand
        case .needsChanges, .duplicate: .warning
        case .rejected: .bad
        case .withdrawn: .neutral
        }
    }

    var symbol: String {
        switch self {
        case .approved: "checkmark.seal.fill"
        case .pendingReview, .draft: "hourglass"
        case .needsChanges: "pencil.circle.fill"
        case .duplicate: "square.on.square"
        case .rejected: "xmark.octagon.fill"
        case .withdrawn: "arrow.uturn.backward.circle"
        }
    }

    var pill: StatusPillModel { StatusPillModel(symbol: symbol, text: title, tone: tone, accessibilityLabel: title) }
}

extension ClaimStatus {
    var title: String {
        switch self {
        case .pendingReview: L10n.Claim.pending
        case .approved: L10n.Claim.approved
        case .rejected: L10n.Claim.rejected
        case .withdrawn: L10n.Claim.withdrawn
        }
    }

    var tone: StatusTone {
        switch self {
        case .pendingReview: .brand
        case .approved: .good
        case .rejected: .bad
        case .withdrawn: .neutral
        }
    }
}

extension ClaimantRole {
    var title: String {
        switch self {
        case .owner: L10n.Claim.owner
        case .manager: L10n.Claim.manager
        case .editor: L10n.Claim.editor
        }
    }
}

extension VenueSummary {
    /// "Café · 350 m" — distance only when known.
    var metaText: String {
        [category.title, distanceMeters.map(Formatters.distance)].compactMap { $0 }.joined(separator: " · ")
    }

    var statusNote: String? {
        switch status {
        case .temporarilyClosed: L10n.Detail.temporarilyClosed
        case .permanentlyClosed: L10n.Detail.permanentlyClosed
        default: nil
        }
    }
}
