import UIKit

/// 1–5 star input. Adjustable with VoiceOver (swipe up/down) and labelled per Product Rules.
final class StarRatingControl: UIControl {
    private(set) var value: Int = 0
    private var buttons: [UIButton] = []
    private let stack = UIStackView()
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
        stack.axis = .horizontal
        stack.spacing = AppSpacing.s
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        for star in 1...5 {
            let button = UIButton(type: .system)
            button.tag = star
            button.addAction(UIAction { [weak self] _ in self?.setValue(star, notify: true) }, for: .primaryActionTriggered)
            button.isAccessibilityElement = false
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        captionLabel.apply(AppTypography.subheadlineEmphasized, color: AppColors.textSecondary)
        captionLabel.textAlignment = .center
        let container = UIStackView(arrangedSubviews: [stack, captionLabel])
        container.axis = .vertical
        container.spacing = AppSpacing.xs
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = true
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = L10n.Review.rating
        render()
    }

    func setValue(_ newValue: Int, notify: Bool = false) {
        let clamped = max(0, min(5, newValue))
        guard clamped != value else { return }
        value = clamped
        render()
        if notify {
            AppComponents.selectionHaptic()
            sendActions(for: .valueChanged)
        }
    }

    private func render() {
        for button in buttons {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: button.tag <= value ? "star.fill" : "star")
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .title1, scale: .large)
            config.baseForegroundColor = button.tag <= value ? AppColors.warning : AppColors.textTertiary
            button.configuration = config
        }
        captionLabel.text = value == 0 ? L10n.Review.ratingRequired : L10n.Rating.starLabel(value)
        accessibilityValue = value == 0 ? L10n.Review.ratingRequired : L10n.Rating.starLabel(value)
    }

    override func accessibilityIncrement() { setValue(value + 1, notify: true) }
    override func accessibilityDecrement() { setValue(value - 1, notify: true) }
}

/// Small read-only star row ("★★★★☆").
enum StarText {
    static func stars(_ rating: Int) -> String {
        String(repeating: "★", count: max(0, min(5, rating))) + String(repeating: "☆", count: max(0, 5 - rating))
    }
}
