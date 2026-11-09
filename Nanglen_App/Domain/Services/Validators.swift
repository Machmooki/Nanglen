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

/// Thai-first phone normalization to E.164 (e.g. "081 234 5678" → "+66812345678").
nonisolated enum PhoneNumberFormatter {
    static func e164(from input: String, defaultCountryCode: String = "66") -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        let candidate: String
        if trimmed.hasPrefix("+") {
            candidate = "+" + digits
        } else if digits.hasPrefix("00") {
            candidate = "+" + digits.dropFirst(2)
        } else if digits.hasPrefix("0") {
            candidate = "+" + defaultCountryCode + digits.dropFirst()
        } else if digits.hasPrefix(defaultCountryCode) {
            candidate = "+" + digits
        } else {
            candidate = "+" + defaultCountryCode + digits
        }
        return isValidE164(candidate) ? candidate : nil
    }

    static func isValidE164(_ value: String) -> Bool {
        guard value.hasPrefix("+") else { return false }
        let digits = value.dropFirst()
        return (8...15).contains(digits.count) && digits.allSatisfy(\.isNumber) && digits.first != "0"
    }

    /// Masked for display, e.g. "+66 •••• 5678".
    static func masked(_ e164: String) -> String {
        guard e164.count > 6 else { return e164 }
        return "\(e164.prefix(3)) •••• \(e164.suffix(4))"
    }
}
