import UIKit

/// Semantic color palette. Brand and surface colors live in the asset catalog
/// (with light + dark variants) so Storyboards and code share the same values.
enum AppColors {
    static let primary = named("BrandPrimary", fallback: .systemTeal)
    static let primarySoft = named("BrandSoft", fallback: .secondarySystemFill)
    static let background = named("AppBackground", fallback: .systemGroupedBackground)
    static let card = named("CardBackground", fallback: .secondarySystemGroupedBackground)

    static let good = named("StatusGood", fallback: .systemGreen)
    static let warning = named("StatusWarning", fallback: .systemOrange)
    static let bad = named("StatusBad", fallback: .systemRed)
    static let neutral = UIColor.systemGray

    static let textPrimary = UIColor.label
    static let textSecondary = UIColor.secondaryLabel
    static let textTertiary = UIColor.tertiaryLabel
    static let fill = UIColor.tertiarySystemFill

    private static func named(_ name: String, fallback: UIColor) -> UIColor {
        UIColor(named: name) ?? fallback
    }
}

/// Visual tone used by status pills, markers and score badges.
enum StatusTone {
    case good
    case warning
    case bad
    case neutral
    case brand

    var foreground: UIColor {
        switch self {
        case .good: AppColors.good
        case .warning: AppColors.warning
        case .bad: AppColors.bad
        case .neutral: AppColors.textSecondary
        case .brand: AppColors.primary
        }
    }

    var background: UIColor {
        switch self {
        case .neutral: AppColors.fill
        case .brand: AppColors.primarySoft
        default: foreground.withAlphaComponent(0.13)
        }
    }
}
