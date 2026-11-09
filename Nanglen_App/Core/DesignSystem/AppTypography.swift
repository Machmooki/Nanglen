import UIKit

/// Type scale. Headings use SF Rounded for a friendly tone; body copy stays on
/// the default system face. Every font scales with Dynamic Type.
enum AppTypography {
    static var largeTitle: UIFont { rounded(.largeTitle, weight: .bold) }
    static var title: UIFont { rounded(.title2, weight: .bold) }
    static var title3: UIFont { rounded(.title3, weight: .semibold) }
    static var headline: UIFont { rounded(.headline, weight: .semibold) }
    static var body: UIFont { scaled(.body, weight: .regular) }
    static var bodyEmphasized: UIFont { scaled(.body, weight: .semibold) }
    static var subheadline: UIFont { scaled(.subheadline, weight: .regular) }
    static var subheadlineEmphasized: UIFont { scaled(.subheadline, weight: .semibold) }
    static var footnote: UIFont { scaled(.footnote, weight: .regular) }
    static var caption: UIFont { scaled(.caption1, weight: .medium) }
    static var captionBold: UIFont { rounded(.caption1, weight: .bold) }
    static var chip: UIFont { rounded(.subheadline, weight: .semibold) }
    static var scoreNumber: UIFont { rounded(.title3, weight: .heavy) }

    /// Base size at the default content size category; UIFontMetrics scales it.
    private static func baseSize(for style: UIFont.TextStyle) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
    }

    static func scaled(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let font = UIFont.systemFont(ofSize: baseSize(for: style), weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    static func rounded(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = baseSize(for: style)
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = system.fontDescriptor.withDesign(.rounded) ?? system.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}

extension UILabel {
    /// Applies a font and opts the label into Dynamic Type updates.
    func apply(_ font: UIFont, color: UIColor = AppColors.textPrimary) {
        self.font = font
        self.textColor = color
        self.adjustsFontForContentSizeCategory = true
    }
}
