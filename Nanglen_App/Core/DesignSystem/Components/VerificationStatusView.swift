import UIKit

/// Card that explains and shows the visit-verification state, with a contextual action.
final class VerificationStatusView: UIView {
    enum Action {
        case retry, openSettings, linkPhone
    }

    var onAction: ((Action) -> Void)?

    private let iconTile = UIView()
    private let iconView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var currentAction: Action?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        AppStyles.card(self, radius: AppRadius.control)
        AppStyles.iconTile(iconTile)
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title3, scale: .medium)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(iconView)
        iconTile.addSubview(spinner)
        iconTile.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.apply(AppTypography.headline)
        titleLabel.numberOfLines = 0
        messageLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        messageLabel.numberOfLines = 0
        actionButton.addAction(UIAction { [weak self] _ in
            if let action = self?.currentAction { self?.onAction?(action) }
        }, for: .primaryActionTriggered)
        actionButton.contentHorizontalAlignment = .leading

        let text = UIStackView(arrangedSubviews: [titleLabel, messageLabel, actionButton])
        text.axis = .vertical
        text.spacing = AppSpacing.xs
        text.alignment = .leading
        let row = UIStackView(arrangedSubviews: [iconTile, text])
        row.axis = .horizontal
        row.spacing = AppSpacing.m
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconTile.widthAnchor.constraint(equalToConstant: 44),
            iconTile.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.l),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.l),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.l),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.l),
        ])
        isAccessibilityElement = false
        render(.idle)
    }

    func render(_ state: VerificationState) {
        let model = Self.model(for: state)
        titleLabel.text = model.title
        messageLabel.text = model.message
        messageLabel.isHidden = model.message == nil
        iconView.image = UIImage(systemName: model.symbol)
        iconView.tintColor = model.tone.foreground
        iconTile.backgroundColor = model.tone.background
        iconView.isHidden = model.loading
        if model.loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        currentAction = model.action
        if let action = model.action {
            var config = UIButton.Configuration.plain()
            config.contentInsets = .zero
            config.title = switch action {
            case .retry: L10n.Review.verifyAgain
            case .openSettings: L10n.Common.openSettings
            case .linkPhone: L10n.Account.linkPhone
            }
            config.baseForegroundColor = AppColors.primary
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = AppTypography.subheadlineEmphasized
                return updated
            }
            actionButton.configuration = config
            actionButton.isHidden = false
        } else {
            actionButton.isHidden = true
        }
        UIAccessibility.post(notification: .layoutChanged, argument: titleLabel)
    }

    private struct Model {
        var symbol: String
        var title: String
        var message: String?
        var tone: StatusTone
        var loading = false
        var action: Action?
    }

    private static func model(for state: VerificationState) -> Model {
        switch state {
        case .idle:
            Model(symbol: "location.circle", title: L10n.Review.explain, message: L10n.Review.spoofDisclaimer, tone: .brand)
        case .requestingPermission:
            Model(symbol: "location", title: L10n.Review.askingPermission, message: L10n.Review.explain, tone: .brand, loading: true)
        case .checkingLocation:
            Model(symbol: "location", title: L10n.Review.checking, message: L10n.Review.explain, tone: .brand, loading: true)
        case .verifying:
            Model(symbol: "location", title: L10n.Review.verifying, message: nil, tone: .brand, loading: true)
        case .verified:
            Model(symbol: "checkmark.seal.fill", title: L10n.Review.verified, message: L10n.Review.spoofDisclaimer, tone: .good)
        case .tooFar(let distance):
            Model(symbol: "location.slash.fill",
                  title: distance.map { L10n.Review.tooFar(Formatters.distance($0)) } ?? L10n.Review.tooFarGeneric,
                  message: nil, tone: .warning, action: .retry)
        case .inaccurate:
            Model(symbol: "scope", title: L10n.Review.inaccurate, message: nil, tone: .warning, action: .retry)
        case .stale:
            Model(symbol: "clock.arrow.circlepath", title: L10n.Review.stale, message: nil, tone: .warning, action: .retry)
        case .unavailable:
            Model(symbol: "location.slash", title: L10n.Review.unavailable, message: nil, tone: .warning, action: .retry)
        case .permissionDenied:
            Model(symbol: "location.slash.fill", title: L10n.Review.permissionDenied, message: nil, tone: .bad, action: .openSettings)
        case .registrationRequired:
            Model(symbol: "person.badge.shield.checkmark", title: L10n.Review.registrationRequired, message: L10n.Account.registeredRequiredReview, tone: .warning, action: .linkPhone)
        case .failed(let message):
            Model(symbol: "exclamationmark.triangle.fill", title: message, message: nil, tone: .bad, action: .retry)
        }
    }
}
