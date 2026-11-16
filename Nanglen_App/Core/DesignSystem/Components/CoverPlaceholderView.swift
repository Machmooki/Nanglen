import UIKit

/// A view backed by a `CAGradientLayer`, so the gradient always fills its bounds.
final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer? { layer as? CAGradientLayer }

    var colors: [UIColor] = [] { didSet { updateColors() } }

    /// Vertical by default (top → bottom).
    func setDirection(start: CGPoint, end: CGPoint) {
        gradientLayer?.startPoint = start
        gradientLayer?.endPoint = end
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GradientView, _: UITraitCollection) in
            view.updateColors()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
    }

    private func updateColors() {
        gradientLayer?.colors = colors.map { $0.resolvedColor(with: traitCollection).cgColor }
    }
}

/// Branded stand-in for a place that has no photos yet: a soft brand gradient with the category symbol.
final class CoverPlaceholderView: UIView {
    private let gradient = GradientView()
    private let symbolView = UIImageView()
    private let captionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        isUserInteractionEnabled = false
        gradient.colors = [AppColors.primarySoft, AppColors.primary.withAlphaComponent(0.28)]
        gradient.setDirection(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1, y: 1))
        symbolView.tintColor = AppColors.primary
        symbolView.contentMode = .scaleAspectFit
        symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        captionLabel.apply(AppTypography.captionBold, color: AppColors.primary.withAlphaComponent(0.8))
        captionLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [symbolView, captionLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.s
        [gradient, stack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            gradient.topAnchor.constraint(equalTo: topAnchor),
            gradient.bottomAnchor.constraint(equalTo: bottomAnchor),
            gradient.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AppSpacing.l),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AppSpacing.l),
        ])
        isAccessibilityElement = false
    }

    func configure(category: VenueCategory, caption: String?) {
        symbolView.image = UIImage(systemName: category.symbol)
        captionLabel.text = caption
        captionLabel.isHidden = caption == nil
    }
}

/// Small capsule that sits on top of a photo (category, rating, photo counter…).
/// `dark` uses a translucent dark blur with white text; `light` is a solid "sticker" with dark text.
final class OverlayChipView: UIView {
    enum Style { case dark, light }

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let iconView = UIImageView()
    private let label = UILabel()
    private let stack = UIStackView()

    init(style: Style) {
        super.init(frame: .zero)
        setUp(style: style)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp(style: .dark)
    }

    private func setUp(style: Style) {
        clipsToBounds = true
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .medium)
        label.apply(AppTypography.captionBold, color: style == .dark ? .white : .black)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
        iconView.tintColor = style == .dark ? .white : AppColors.warning

        switch style {
        case .dark:
            blurView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(blurView)
            NSLayoutConstraint.activate([
                blurView.topAnchor.constraint(equalTo: topAnchor),
                blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
                blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
                blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            backgroundColor = UIColor.black.withAlphaComponent(0.15)
        case .light:
            backgroundColor = UIColor.white.withAlphaComponent(0.94)
        }

        stack.axis = .horizontal
        stack.spacing = AppSpacing.xs
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func configure(symbol: String?, text: String, iconColor: UIColor? = nil, textColor: UIColor? = nil) {
        iconView.image = symbol.flatMap { UIImage(systemName: $0) }
        iconView.isHidden = iconView.image == nil
        if let iconColor { iconView.tintColor = iconColor }
        if let textColor { label.textColor = textColor }
        label.text = text
    }
}
