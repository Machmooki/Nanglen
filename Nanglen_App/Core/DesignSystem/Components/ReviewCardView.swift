import UIKit

/// One published review (current revision). Shows the reviewer's display name only.
final class ReviewCardView: UIView {
    var onReport: (() -> Void)?
    /// All photo URLs of the review and the tapped index (opens the full-screen viewer).
    var onPhotoTap: (([URL], Int) -> Void)?

    private let authorLabel = UILabel()
    private let badgeLabel = UILabel()
    private let starsLabel = UILabel()
    private let metaLabel = UILabel()
    private let bodyLabel = UILabel()
    private let tagsView = TagPillsView()
    private let photosStack = UIStackView()
    private let photosScroll = UIScrollView()
    private var photoURLs: [URL] = []
    private let menuButton = UIButton(type: .system)

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
        layer.shadowOpacity = 0.03
        authorLabel.apply(AppTypography.subheadlineEmphasized)
        badgeLabel.apply(AppTypography.caption, color: AppColors.good)
        badgeLabel.text = "✓ " + L10n.Detail.verifiedVisit
        starsLabel.apply(AppTypography.subheadline, color: AppColors.warning)
        metaLabel.apply(AppTypography.caption, color: AppColors.textSecondary)
        bodyLabel.apply(AppTypography.body)
        bodyLabel.numberOfLines = 0
        tagsView.spacing = AppSpacing.xs
        tagsView.lineSpacing = AppSpacing.xs
        photosStack.axis = .horizontal
        photosStack.spacing = AppSpacing.s
        photosScroll.showsHorizontalScrollIndicator = false
        photosScroll.alwaysBounceHorizontal = false
        photosStack.translatesAutoresizingMaskIntoConstraints = false
        photosScroll.addSubview(photosStack)
        NSLayoutConstraint.activate([
            photosStack.topAnchor.constraint(equalTo: photosScroll.contentLayoutGuide.topAnchor),
            photosStack.bottomAnchor.constraint(equalTo: photosScroll.contentLayoutGuide.bottomAnchor),
            photosStack.leadingAnchor.constraint(equalTo: photosScroll.contentLayoutGuide.leadingAnchor),
            photosStack.trailingAnchor.constraint(equalTo: photosScroll.contentLayoutGuide.trailingAnchor),
            photosStack.heightAnchor.constraint(equalTo: photosScroll.frameLayoutGuide.heightAnchor),
            photosScroll.heightAnchor.constraint(equalToConstant: Self.thumbnailSize),
        ])

        var menuConfig = UIButton.Configuration.plain()
        menuConfig.image = UIImage(systemName: "ellipsis")
        menuConfig.baseForegroundColor = AppColors.textSecondary
        menuButton.configuration = menuConfig
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityLabel = L10n.Detail.report
        menuButton.menu = UIMenu(children: [UIAction(title: L10n.Detail.report, image: UIImage(systemName: "flag"), attributes: .destructive) { [weak self] _ in
            self?.onReport?()
        }])
        menuButton.setContentHuggingPriority(.required, for: .horizontal)

        let nameRow = UIStackView(arrangedSubviews: [authorLabel, UIView(), menuButton])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        let starRow = UIStackView(arrangedSubviews: [starsLabel, metaLabel])
        starRow.axis = .horizontal
        starRow.spacing = AppSpacing.s
        starRow.alignment = .firstBaseline
        let stack = UIStackView(arrangedSubviews: [nameRow, starRow, badgeLabel, bodyLabel, tagsView, photosScroll])
        stack.axis = .vertical
        stack.spacing = AppSpacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.m),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.l),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.l),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.s),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        AppStyles.updateShadowPath(self)
    }

    func configure(_ review: PublishedReview, photoURLs: [URL]) {
        authorLabel.text = review.isMine ? "\(review.authorName) (\(L10n.Detail.you))" : review.authorName
        starsLabel.text = StarText.stars(review.rating)
        metaLabel.text = [review.purpose?.title, Formatters.relative(review.updatedAt)].compactMap { $0 }.joined(separator: " · ")
        badgeLabel.isHidden = !review.isVerifiedVisit
        bodyLabel.text = review.body
        bodyLabel.isHidden = review.body == nil
        tagsView.configure(review.tags.map { ReviewTag.pill(for: $0) })
        tagsView.isHidden = review.tags.isEmpty
        menuButton.isHidden = review.isMine
        configurePhotos(photoURLs)
        isAccessibilityElement = false
        accessibilityElements = [authorLabel, starsLabel, metaLabel, badgeLabel, bodyLabel, tagsView] + photosStack.arrangedSubviews + [menuButton]
        starsLabel.accessibilityLabel = L10n.Rating.starLabel(review.rating)
    }
}

extension ReviewCardView {
    static let thumbnailSize: CGFloat = 84

    /// Every photo of the review (server limit, currently 5) as a horizontally scrolling row of thumbnails.
    private func configurePhotos(_ urls: [URL]) {
        photoURLs = urls
        let thumbnails: [UIView] = urls.enumerated().map { index, url in
            let button = UIButton(type: .custom)
            let imageView = RemoteImageView(frame: CGRect(x: 0, y: 0, width: Self.thumbnailSize, height: Self.thumbnailSize))
            imageView.isUserInteractionEnabled = false
            imageView.load(url, maxPixelSize: Self.thumbnailSize * 3)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(imageView)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.thumbnailSize),
                button.heightAnchor.constraint(equalToConstant: Self.thumbnailSize),
                imageView.topAnchor.constraint(equalTo: button.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            ])
            button.accessibilityLabel = L10n.Detail.photoPosition(index + 1, urls.count)
            button.accessibilityTraits = [.button, .image]
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                onPhotoTap?(photoURLs, index)
            }, for: .primaryActionTriggered)
            return button
        }
        AppComponents.replaceArrangedSubviews(of: photosStack, with: thumbnails)
        photosScroll.isHidden = urls.isEmpty
        photosScroll.contentOffset = .zero
    }
}

/// Minimal async image view for signed URLs (Storage) or local demo files. No third-party loader.
final class RemoteImageView: UIImageView {
    private var task: Task<Void, Never>?
    private static let cache = NSCache<NSURL, UIImage>()

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    override init(image: UIImage?) {
        super.init(image: image)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = AppRadius.small
        layer.cornerCurve = .continuous
        backgroundColor = AppColors.fill
    }

    /// - Parameter maxPixelSize: decode size cap in pixels; defaults to the view's current size.
    ///   Pass one when the view isn't laid out yet (e.g. a cell or page that was just created).
    func load(_ url: URL?, maxPixelSize: CGFloat? = nil) {
        task?.cancel()
        image = nil
        guard let url else { return }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        // Read and decode off the main thread; a decoded image draws without a hitch while scrolling.
        let target = maxPixelSize ?? max(bounds.width, bounds.height, 120) * max(traitCollection.displayScale, 1)
        task = Task { [weak self] in
            let image = await Self.decodedImage(at: url, maxPixelSize: target)
            guard !Task.isCancelled, let image else { return }
            Self.cache.setObject(image, forKey: url as NSURL)
            self?.image = image
        }
    }

    /// `@concurrent` keeps this off the main actor (the project uses approachable concurrency).
    @concurrent
    private nonisolated static func decodedImage(at url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let data: Data?
        if url.isFileURL {
            data = try? Data(contentsOf: url)
        } else {
            data = try? await URLSession.shared.data(from: url).0
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height) * image.scale
        if longest > maxPixelSize, longest > 0 {
            let ratio = maxPixelSize / longest
            let size = CGSize(width: image.size.width * image.scale * ratio, height: image.size.height * image.scale * ratio)
            if let thumbnail = await image.byPreparingThumbnail(ofSize: size) { return thumbnail }
        }
        return await image.byPreparingForDisplay() ?? image
    }
}
