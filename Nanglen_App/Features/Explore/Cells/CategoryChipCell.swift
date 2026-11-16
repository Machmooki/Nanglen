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
        contentView.layer.cornerCurve = .continuous
        titleLabel.apply(AppTypography.chip)
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: CategoryChipCell, _: UITraitCollection) in
            cell.updateAppearance()
        }
        updateAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.cornerRadius = contentView.bounds.height / 2
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
        // Filled brand capsule when selected, soft brand tint otherwise (no outlines: cleaner, more modern).
        contentView.backgroundColor = isSelected ? AppColors.primary : AppColors.primarySoft
        titleLabel.textColor = isSelected ? .white : AppColors.primary
        iconImageView.tintColor = isSelected ? .white : AppColors.primary
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
