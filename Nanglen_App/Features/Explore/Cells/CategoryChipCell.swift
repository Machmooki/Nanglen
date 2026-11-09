import UIKit

/// Quick category chip (prototype cell in Main.storyboard → Explore).
final class CategoryChipCell: UICollectionViewCell {
    static let reuseIdentifier = "CategoryChipCell"

    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!

    // UICollectionReusableView declares awakeFromNib nonisolated; nibs are
    // always decoded on the main thread.
    nonisolated override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { setUp() }
    }

    private func setUp() {
        contentView.layer.cornerRadius = 18
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        titleLabel.apply(AppTypography.chip)
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: CategoryChipCell, _: UITraitCollection) in
            cell.updateAppearance()
        }
        updateAppearance()
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    func configure(title: String, symbol: String?) {
        titleLabel.text = title
        iconImageView.image = symbol.flatMap { UIImage(systemName: $0) }
        iconImageView.isHidden = symbol == nil
        accessibilityLabel = title
    }

    private func updateAppearance() {
        contentView.backgroundColor = isSelected ? AppColors.primary : AppColors.card
        titleLabel.textColor = isSelected ? .white : AppColors.textPrimary
        iconImageView.tintColor = isSelected ? .white : AppColors.primary
        let border = isSelected ? UIColor.clear : UIColor.separator.withAlphaComponent(0.4)
        contentView.layer.borderColor = border.resolvedColor(with: traitCollection).cgColor
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
