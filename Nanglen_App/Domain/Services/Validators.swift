import Foundation

/// Client-side validation for fast feedback. The server validates everything again.
nonisolated enum ReviewValidator {
    enum Issue: Error, Hashable, Sendable {
        case ratingRequired
        case tooManyTags(max: Int)
        case bodyTooLong(max: Int)
    }

    static func issues(rating: Int?, tags: [String], body: String, maxTags: Int, maxBody: Int) -> [Issue] {
        var issues: [Issue] = []
        if rating.map({ !(1...5).contains($0) }) ?? true { issues.append(.ratingRequired) }
        if Set(tags).count > maxTags { issues.append(.tooManyTags(max: maxTags)) }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).count > maxBody { issues.append(.bodyTooLong(max: maxBody)) }
        return issues
    }

    static func validate(rating: Int?, tags: [String], body: String, maxTags: Int, maxBody: Int) throws {
        if let first = issues(rating: rating, tags: tags, body: body, maxTags: maxTags, maxBody: maxBody).first {
            switch first {
            case .ratingRequired: throw BackendError.invalidInput("invalid_rating")
            case .tooManyTags: throw BackendError.invalidInput("too_many_tags")
            case .bodyTooLong: throw BackendError.invalidInput("body_too_long")
            }
        }
    }
}

nonisolated enum SubmissionValidator {
    enum Issue: Error, Hashable, Sendable {
        case nameRequired
        case categoryRequired
        case locationRequired
        case invalidWebsite
        case textTooLong
    }

    static func issues(_ draft: VenueSubmissionDraft) -> [Issue] {
        var issues: [Issue] = []
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { issues.append(.nameRequired) }
        if draft.category == nil { issues.append(.categoryRequired) }
        if draft.coordinate.map({ !$0.isValid }) ?? true { issues.append(.locationRequired) }
        let website = draft.websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !website.isEmpty {
            let lower = website.lowercased()
            if !(lower.hasPrefix("http://") || lower.hasPrefix("https://")) || URL(string: website)?.host == nil {
                issues.append(.invalidWebsite)
            }
        }
        if name.count > 120 || draft.address.count > 300 || draft.description.count > 1_000 || draft.note.count > 500 {
            issues.append(.textTooLong)
        }
        return issues
    }

    static func validate(_ draft: VenueSubmissionDraft) throws {
        if let first = issues(draft).first {
            switch first {
            case .nameRequired: throw BackendError.invalidInput("name_required")
            case .categoryRequired: throw BackendError.invalidInput("category_required")
            case .locationRequired: throw BackendError.invalidInput("invalid_coordinate")
            case .invalidWebsite: throw BackendError.invalidInput("invalid_website_url")
            case .textTooLong: throw BackendError.invalidInput("text_too_long")
            }
        }
    }
}

/// Email normalisation and masking. The backend verifies ownership with a one-time code.
nonisolated enum EmailAddress {
    static func normalized(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.count <= 254, value.filter({ $0 == "@" }).count == 1 else { return nil }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].count <= 64,
              parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              value.allSatisfy({ !$0.isWhitespace && !$0.isNewline }) else { return nil }
        return value
    }

    /// "mint@gmail.com" → "m•••@gmail.com".
    static func masked(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, let first = parts[0].first else { return "•••" }
        return "\(first)•••@\(parts[1])"
    }
}

/// Mirrors the server's display-name rules (`update_my_display_name`) for instant feedback.
nonisolated enum DisplayNamePolicy {
    private static let invisible = CharacterSet(charactersIn: "\u{200B}\u{200C}\u{200D}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2060}\u{2066}\u{2067}\u{2068}\u{2069}\u{FEFF}")
        .union(.controlCharacters)
    private static let reserved = ["admin", "moderator", "nanglen", "official", "support", "staff", "ผู้ดูแล", "แอดมิน", "ทีมงาน"]

    static func clean(_ name: String) -> String {
        let visible = String(String.UnicodeScalarView(name.unicodeScalars.filter { !invisible.contains($0) }))
        return visible.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func isReserved(_ name: String) -> Bool {
        let lower = name.lowercased()
        return reserved.contains { lower.contains($0) }
    }
}

/// Only plain web links from user-submitted data are ever opened (no `javascript:`, app schemes, files).
nonisolated enum SafeLink {
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
}
