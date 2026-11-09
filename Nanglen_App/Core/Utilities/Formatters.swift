import Foundation

/// Locale-aware formatting that follows the app's language (Thai by default),
/// not the device region, so numbers and words never mix languages.
enum Formatters {
    static var appLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "th")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = appLocale
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func distance(_ meters: Double) -> String {
        if meters < 1_000 {
            let rounded = max(10, (meters / 10).rounded() * 10)
            return String(localized: "\(Int(rounded)) ม.")
        }
        let km = meters / 1_000
        let value = km < 10 ? km.formatted(.number.precision(.fractionLength(1)).locale(appLocale)) : "\(Int(km.rounded()))"
        return String(localized: "\(value) กม.")
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return String(localized: "เมื่อสักครู่") }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
