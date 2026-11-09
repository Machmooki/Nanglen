import UIKit

/// Reusable approved-venue card (PlaceCardCell.xib) used by Explore and Saved.
final class PlaceCardCell: UITableViewCell {
    static let reuseIdentifier = "PlaceCardCell"
    static var nib: UINib { UINib(nibName: "PlaceCardCell", bundle: nil) }

    @IBOutlet private weak var cardView: UIView!
    @IBOutlet private weak var iconTileView: UIView!
    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var metaLabel: UILabel!
    @IBOutlet private weak var favoriteImageView: UIImageView!
    @IBOutlet private weak var ratingBadgeView: RatingBadgeView!
    @IBOutlet private weak var pillsStackView: UIStackView!
    @IBOutlet private weak var footerLabel: UILabel!

    private var pillViews: [StatusPillView] = []
    private let coverView = RemoteImageView()

    // UIView declares awakeFromNib nonisolated; nibs always load on the main thread.
    nonisolated override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated { setUp() }
    }

    private func setUp() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        AppStyles.card(cardView)
        AppStyles.iconTile(iconTileView)
        iconImageView.tintColor = AppColors.primary
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title3, scale: .medium)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.layer.cornerRadius = AppRadius.icon
        coverView.isHidden = true
        iconTileView.addSubview(coverView)
        NSLayoutConstraint.activate([
            coverView.topAnchor.constraint(equalTo: iconTileView.topAnchor),
            coverView.bottomAnchor.constraint(equalTo: iconTileView.bottomAnchor),
            coverView.leadingAnchor.constraint(equalTo: iconTileView.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: iconTileView.trailingAnchor),
        ])
        nameLabel.apply(AppTypography.headline)
        metaLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        footerLabel.apply(AppTypography.caption, color: AppColors.textTertiary)
        favoriteImageView.tintColor = AppColors.bad
        pillViews = (0..<3).map { _ in StatusPillView() }
        AppComponents.replaceArrangedSubviews(of: pillsStackView, with: pillViews)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.load(nil)
        coverView.isHidden = true
    }

    func configure(with item: VenueCardItem, coverURL: URL? = nil) {
        let venue = item.venue
        iconImageView.image = UIImage(systemName: venue.category.symbol)
        coverView.isHidden = coverURL == nil
        coverView.load(coverURL)
        nameLabel.text = venue.name
        metaLabel.text = venue.metaText
        favoriteImageView.isHidden = !item.isFavorite
        ratingBadgeView.configure(venue.rating)
        let tags = venue.topTags.prefix(3).map { ReviewTag.pill(for: $0) }
        for (index, pill) in pillViews.enumerated() {
            if index < tags.count {
                pill.configure(tags[index])
                pill.isHidden = false
            } else {
                pill.isHidden = true
            }
        }
        pillsStackView.isHidden = tags.isEmpty
        var footer: [String] = []
        if let note = venue.statusNote { footer.append(note) }
        if !tags.isEmpty { footer.append(L10n.Detail.communityTagsNote) }
        if !venue.rating.hasReviews { footer.append(L10n.Detail.noReviewsMessage) }
        footerLabel.text = footer.joined(separator: " · ")
        footerLabel.textColor = venue.statusNote == nil ? AppColors.textTertiary : AppColors.warning

        let tagText = tags.map(\.accessibilityLabel).joined(separator: ", ")
        accessibilityLabel = [venue.name, venue.metaText, venue.rating.accessibilityText, tagText, venue.statusNote]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        AppComponents.animatePress(cardView, pressed: highlighted)
    }
}
