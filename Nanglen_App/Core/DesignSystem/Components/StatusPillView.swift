import UIKit

/// Compact capsule showing an SF Symbol and a short value, tinted by tone.
final class StatusPillView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        layer.cornerCurve = .continuous
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .medium)
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        label.apply(AppTypography.captionBold)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.axis = .horizontal
        stack.spacing = AppSpacing.xs
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.s),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.s),
        ])
        isAccessibilityElement = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    func configure(_ model: StatusPillModel) {
        iconView.image = UIImage(systemName: model.symbol)
        label.text = model.text
        iconView.tintColor = model.tone.foreground
        label.textColor = model.tone.foreground
        backgroundColor = model.tone.background
        accessibilityLabel = model.accessibilityLabel
    }
}

struct StatusPillModel: Hashable {
    let symbol: String
    let text: String
    let tone: StatusTone
    let accessibilityLabel: String
}
