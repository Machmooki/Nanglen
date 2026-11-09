import UIKit

/// Table section header with a rounded title and optional supporting text.
final class SectionHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "SectionHeaderView"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        var background = UIBackgroundConfiguration.clear()
        background.backgroundColor = .clear
        backgroundConfiguration = background

        titleLabel.apply(AppTypography.title3)
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        subtitleLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = AppSpacing.xxs
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.l),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.xs),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.screenMargin),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.screenMargin),
        ])
    }

    func configure(title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
    }
}
