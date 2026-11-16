import UIKit

/// Photo-first venue card for Explore: a big cover photo (or branded placeholder) with the category and
/// favorite on top, then name, rating, distance and up to two "good for" tags.
/// Built in code so the layout is easy to tweak; Saved still uses the compact `PlaceCardCell`.
final class ExplorePlaceCardCell: UITableViewCell {
    static let reuseIdentifier = "ExplorePlaceCardCell"
    private static let coverHeight: CGFloat = 172
    private static let maxTags = 2

    private let cardView = UIView()
    private let coverContainer = UIView()
    private let placeholderView = CoverPlaceholderView()
    // A non-zero frame makes `RemoteImageView` decode at card size instead of thumbnail size.
    private let coverView = RemoteImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 172))
    private let scrimView = GradientView()
    private let categoryChip = OverlayChipView(style: .dark)
    private let favoriteBadge = UIImageView()
    private let favoriteBackground = UIView()

    private let nameLabel = UILabel()
    private let ratingChip = OverlayChipView(style: .light)
    private let metaLabel = UILabel()
    private let tagsStack = UIStackView()
    private let statusLabel = UILabel()
    private var tagViews: [StatusPillView] = []
    private let moreTagsLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    // MARK: Setup

    private func setUp() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        AppStyles.card(cardView, radius: AppRadius.card + 4)

        setUpCover()
        setUpInfo()

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.s),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.s),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.screenMargin),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.screenMargin),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private func setUpCover() {
        coverContainer.clipsToBounds = true
        coverContainer.layer.cornerRadius = AppRadius.card - 2
        coverContainer.layer.cornerCurve = .continuous
        coverContainer.backgroundColor = AppColors.primarySoft
        coverView.layer.cornerRadius = 0

        scrimView.colors = [UIColor.black.withAlphaComponent(0.28), .clear, .clear]
        scrimView.setDirection(start: CGPoint(x: 0.5, y: 0), end: CGPoint(x: 0.5, y: 1))

        favoriteBackground.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        favoriteBackground.layer.cornerRadius = 16
        favoriteBadge.image = UIImage(systemName: "heart.fill")
        favoriteBadge.tintColor = AppColors.bad
        favoriteBadge.contentMode = .scaleAspectFit
        favoriteBadge.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)

        [placeholderView, coverView, scrimView, categoryChip, favoriteBackground].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            coverContainer.addSubview($0)
        }
        favoriteBadge.translatesAutoresizingMaskIntoConstraints = false
        favoriteBackground.addSubview(favoriteBadge)

        let fills: [UIView] = [placeholderView, coverView, scrimView]
        var constraints = fills.flatMap { view in [
            view.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor),
        ] }
        constraints += [
            categoryChip.topAnchor.constraint(equalTo: coverContainer.topAnchor, constant: AppSpacing.m),
            categoryChip.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor, constant: AppSpacing.m),
            favoriteBackground.topAnchor.constraint(equalTo: coverContainer.topAnchor, constant: AppSpacing.m),
            favoriteBackground.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor, constant: -AppSpacing.m),
            favoriteBackground.widthAnchor.constraint(equalToConstant: 32),
            favoriteBackground.heightAnchor.constraint(equalToConstant: 32),
            favoriteBadge.centerXAnchor.constraint(equalTo: favoriteBackground.centerXAnchor),
            favoriteBadge.centerYAnchor.constraint(equalTo: favoriteBackground.centerYAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
    }

    private func setUpInfo() {
        nameLabel.apply(AppTypography.headline)
        nameLabel.numberOfLines = 2
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The name takes the spare width so the rating chip stays snug around "★ 4.3".
        nameLabel.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        metaLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        metaLabel.numberOfLines = 1
        statusLabel.apply(AppTypography.footnote, color: AppColors.warning)
        statusLabel.numberOfLines = 0
        ratingChip.setContentHuggingPriority(.required, for: .horizontal)
        ratingChip.setContentCompressionResistancePriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [nameLabel, ratingChip])
        titleRow.axis = .horizontal
        titleRow.alignment = .top
        titleRow.spacing = AppSpacing.s

        tagViews = (0..<Self.maxTags).map { _ in StatusPillView() }
        moreTagsLabel.apply(AppTypography.captionBold, color: AppColors.primary)
        moreTagsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        tagsStack.axis = .horizontal
        tagsStack.alignment = .center
        tagsStack.spacing = AppSpacing.xs + 2
        (tagViews + [moreTagsLabel]).forEach(tagsStack.addArrangedSubview)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tagsStack.addArrangedSubview(spacer)

        let info = UIStackView(arrangedSubviews: [titleRow, metaLabel, tagsStack, statusLabel])
        info.axis = .vertical
        info.spacing = AppSpacing.xs + 2
        info.setCustomSpacing(AppSpacing.s + 2, after: metaLabel)

        [coverContainer, info].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview($0)
        }
        NSLayoutConstraint.activate([
            coverContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: AppSpacing.s),
            coverContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: AppSpacing.s),
            coverContainer.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -AppSpacing.s),
            coverContainer.heightAnchor.constraint(equalToConstant: Self.coverHeight),
            info.topAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: AppSpacing.m),
            info.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: AppSpacing.l),
            info.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -AppSpacing.l),
            info.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -AppSpacing.l),
        ])
    }

    // MARK: Lifecycle

    override func layoutSubviews() {
        super.layoutSubviews()
        AppStyles.updateShadowPath(cardView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverView.load(nil)
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        AppComponents.animatePress(cardView, pressed: highlighted)
    }

    // MARK: Configure

    func configure(with item: VenueCardItem) {
        let venue = item.venue

        placeholderView.configure(category: venue.category, caption: item.coverURL == nil ? L10n.Explore.noPhotosYet : nil)
        coverView.isHidden = item.coverURL == nil
        scrimView.isHidden = item.coverURL == nil
        coverView.load(item.coverURL, maxPixelSize: 1_200)
        categoryChip.configure(symbol: venue.category.symbol, text: venue.category.title)
        favoriteBackground.isHidden = !item.isFavorite

        nameLabel.text = venue.name
        if venue.rating.hasReviews, let average = venue.rating.average {
            ratingChip.backgroundColor = StatusTone.warning.background
            ratingChip.configure(symbol: "star.fill", text: RatingSummary.format(average), iconColor: AppColors.warning, textColor: AppColors.textPrimary)
        } else {
            ratingChip.backgroundColor = StatusTone.brand.background
            ratingChip.configure(symbol: "sparkles", text: L10n.Explore.newPlace, iconColor: AppColors.primary, textColor: AppColors.primary)
        }

        var meta: [String] = []
        if let distance = venue.distanceMeters { meta.append(L10n.Explore.distanceAway(Formatters.distance(distance))) }
        meta.append(venue.rating.hasReviews ? L10n.Rating.reviewCount(venue.rating.reviewCount) : L10n.Rating.noReviews)
        metaLabel.text = meta.joined(separator: " · ")

        let tags = item.displayTags.map { ReviewTag.pill(for: $0) }
        for (index, view) in tagViews.enumerated() {
            if index < tags.count {
                view.configure(tags[index])
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }
        let extra = tags.count - Self.maxTags
        moreTagsLabel.text = extra > 0 ? "+\(extra)" : nil
        moreTagsLabel.isHidden = extra <= 0
        tagsStack.isHidden = tags.isEmpty

        statusLabel.text = venue.statusNote
        statusLabel.isHidden = venue.statusNote == nil

        let tagText = tags.map(\.accessibilityLabel).joined(separator: ", ")
        accessibilityLabel = [venue.name, venue.category.title, metaLabel.text, venue.rating.accessibilityText, tagText,
                              item.isFavorite ? L10n.Explore.savedBadge : nil, venue.statusNote]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
