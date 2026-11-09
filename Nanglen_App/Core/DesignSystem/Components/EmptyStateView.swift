import UIKit

/// Centered illustration + message used for empty, loading and error states.
final class EmptyStateView: UIView {
    struct Model {
        var symbol: String?
        var title: String
        var message: String?
        var actionTitle: String?
        var isLoading: Bool = false
    }

    var onAction: (() -> Void)?

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
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
        AppStyles.iconTile(iconContainer)
        iconContainer.layer.cornerRadius = 28
        iconView.tintColor = AppColors.primary
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = AppColors.primary

        titleLabel.apply(AppTypography.title3)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        messageLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .primaryActionTriggered)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        [iconContainer, spinner, titleLabel, messageLabel, actionButton].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(AppSpacing.l, after: iconContainer)
        stack.setCustomSpacing(AppSpacing.l, after: spinner)
        stack.setCustomSpacing(AppSpacing.xl, after: messageLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 64),
            iconContainer.heightAnchor.constraint(equalToConstant: 64),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -24),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: AppSpacing.l),
        ])
    }

    func configure(_ model: Model) {
        iconView.image = model.symbol.flatMap { UIImage(systemName: $0) }
        iconContainer.isHidden = model.symbol == nil || model.isLoading
        spinner.isHidden = !model.isLoading
        if model.isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
        titleLabel.text = model.title
        messageLabel.text = model.message
        messageLabel.isHidden = model.message == nil
        if let actionTitle = model.actionTitle {
            AppStyles.secondaryButton(actionButton, title: actionTitle)
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
    }
}
