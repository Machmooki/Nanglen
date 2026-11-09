import UIKit

/// Reusable styling recipes. Screens call these instead of hand-tuning layers,
/// so every card, button and bar looks the same across the app.
enum AppStyles {
    static func applyGlobalAppearance(to window: UIWindow?) {
        window?.tintColor = AppColors.primary
        let largeTitle = [NSAttributedString.Key.font: AppTypography.largeTitle]
        UINavigationBar.appearance().largeTitleTextAttributes = largeTitle
        UINavigationBar.appearance().titleTextAttributes = [.font: AppTypography.headline]
    }

    static func card(_ view: UIView, radius: CGFloat = AppRadius.card) {
        view.backgroundColor = AppColors.card
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.06
        view.layer.shadowRadius = 14
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    static func iconTile(_ view: UIView, tone: StatusTone = .brand) {
        view.backgroundColor = tone.background
        view.layer.cornerRadius = AppRadius.icon
        view.layer.cornerCurve = .continuous
    }

    static func primaryButton(_ button: UIButton, title: String, systemImage: String? = nil) {
        var config = UIButton.Configuration.prominentGlass()
        config.title = title
        config.baseBackgroundColor = AppColors.primary
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.buttonSize = .large
        config.imagePadding = AppSpacing.s
        if let systemImage { config.image = UIImage(systemName: systemImage) }
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = AppTypography.headline
            return updated
        }
        button.configuration = config
    }

    static func secondaryButton(_ button: UIButton, title: String?, systemImage: String? = nil) {
        var config = UIButton.Configuration.glass()
        config.title = title
        config.baseForegroundColor = AppColors.primary
        config.cornerStyle = .capsule
        config.buttonSize = .large
        config.imagePadding = AppSpacing.s
        if let systemImage { config.image = UIImage(systemName: systemImage) }
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = AppTypography.headline
            return updated
        }
        button.configuration = config
    }

    static func overlayButton(_ button: UIButton, title: String?, systemImage: String) {
        var config = UIButton.Configuration.glass()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = AppSpacing.xs
        config.cornerStyle = .capsule
        config.baseForegroundColor = AppColors.primary
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = AppTypography.subheadlineEmphasized
            return updated
        }
        button.configuration = config
    }

    static func segmentedControl(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = AppColors.primary
        control.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: AppTypography.subheadlineEmphasized], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: AppColors.textPrimary, .font: AppTypography.subheadline], for: .normal)
    }

    static func sectionTitle(_ label: UILabel) {
        label.apply(AppTypography.headline)
        label.numberOfLines = 0
    }
}
