import UIKit

/// Compact average-rating badge. With no reviews it says so — it never shows 0.0.
final class RatingBadgeView: UIView {
    private let valueLabel = UILabel()
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
        layer.cornerRadius = AppRadius.icon
        layer.cornerCurve = .continuous
        valueLabel.apply(AppTypography.scoreNumber)
        valueLabel.textAlignment = .center
        captionLabel.apply(AppTypography.captionBold)
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.xs),
        ])
        isAccessibilityElement = true
    }

    func configure(_ rating: RatingSummary) {
        if rating.hasReviews, let average = rating.average {
            valueLabel.isHidden = false
            valueLabel.text = "★ " + RatingSummary.format(average)
            valueLabel.textColor = AppColors.textPrimary
            captionLabel.text = L10n.Rating.reviewCount(rating.reviewCount)
            captionLabel.textColor = AppColors.textSecondary
            backgroundColor = StatusTone.warning.background
        } else {
            valueLabel.isHidden = true
            captionLabel.text = L10n.Rating.noReviews
            captionLabel.textColor = AppColors.textSecondary
            backgroundColor = AppColors.fill
        }
        accessibilityLabel = rating.accessibilityText
    }
}
