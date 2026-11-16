import UIKit

/// List footer: "load more" and the "missing a place?" call to action (Add Place).
final class ExploreFooterView: UIView {
    var onAddPlace: (() -> Void)?
    var onLoadMore: (() -> Void)?

    private let loadMoreButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let messageLabel = UILabel()
    private let addButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        messageLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        messageLabel.text = L10n.Explore.missingPlaceFooter
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        AppStyles.secondaryButton(addButton, title: L10n.Explore.addPlace, systemImage: "plus.circle.fill")
        addButton.addAction(UIAction { [weak self] _ in self?.onAddPlace?() }, for: .primaryActionTriggered)
        addButton.accessibilityIdentifier = "explore.addPlace"
        var config = UIButton.Configuration.plain()
        config.title = L10n.Explore.loadMore
        loadMoreButton.configuration = config
        loadMoreButton.addAction(UIAction { [weak self] _ in self?.onLoadMore?() }, for: .primaryActionTriggered)
        spinner.color = AppColors.primary

        // Add Place now lives in Explore's floating button; the footer only handles "load more".
        messageLabel.isHidden = true
        addButton.isHidden = true
        addButton.accessibilityIdentifier = nil

        let stack = UIStackView(arrangedSubviews: [loadMoreButton, spinner, messageLabel, addButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.l),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.xxl),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.screenMargin),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.screenMargin),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(hasMore: Bool, isLoadingMore: Bool) {
        loadMoreButton.isHidden = !hasMore || isLoadingMore
        spinner.isHidden = !isLoadingMore
        if isLoadingMore { spinner.startAnimating() } else { spinner.stopAnimating() }
    }
}
