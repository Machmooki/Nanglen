import UIKit

/// Full-width, swipeable photo carousel at the top of Venue Detail.
/// Shows a "1 / 4" counter and, when available, a 360° button. Falls back to a branded placeholder
/// when the place has no photos yet.
final class VenueHeroGalleryView: UIView, UIScrollViewDelegate {
    enum Panorama: Equatable {
        case none
        /// The place's own 360° photo.
        case photo
        /// Apple Maps Look Around (street-level 360°) at the place's location.
        case lookAround
    }

    static let height: CGFloat = 264

    var onShow360: (() -> Void)?

    private let scrollView = UIScrollView()
    private let pagesStack = UIStackView()
    private let placeholder = CoverPlaceholderView()
    private let counterChip = OverlayChipView(style: .dark)
    private let view360Button = UIButton(type: .system)
    private var urls: [URL] = []
    private var currentPage = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        clipsToBounds = true
        layer.cornerRadius = AppRadius.card
        layer.cornerCurve = .continuous
        backgroundColor = AppColors.primarySoft

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        pagesStack.axis = .horizontal
        pagesStack.distribution = .fill

        view360Button.addAction(UIAction { [weak self] _ in self?.onShow360?() }, for: .primaryActionTriggered)
        view360Button.isHidden = true

        [placeholder, scrollView, counterChip, view360Button].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        pagesStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(pagesStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            placeholder.topAnchor.constraint(equalTo: topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pagesStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            pagesStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            pagesStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            counterChip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.m),
            counterChip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.m),
            view360Button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.m),
            view360Button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.m),
            view360Button.trailingAnchor.constraint(lessThanOrEqualTo: counterChip.leadingAnchor, constant: -AppSpacing.s),
        ])
    }

    /// Rebuilds the pages only when the photo list changes, so swiping position survives re-renders.
    /// - Parameter isLoading: hides the "No photos yet" caption while photos may still be on their way.
    func configure(photoURLs: [URL], category: VenueCategory, panorama: Panorama, isLoading: Bool) {
        if photoURLs != urls {
            urls = photoURLs
            currentPage = 0
            scrollView.contentOffset = .zero
            let pages: [UIView] = photoURLs.enumerated().map { index, url in
                // A real frame makes RemoteImageView decode at full card width instead of thumbnail size.
                let imageView = RemoteImageView(frame: CGRect(x: 0, y: 0, width: 430, height: Self.height))
                imageView.layer.cornerRadius = 0
                imageView.isAccessibilityElement = true
                imageView.accessibilityTraits = .image
                imageView.accessibilityLabel = L10n.Detail.photoPosition(index + 1, photoURLs.count)
                imageView.load(url, maxPixelSize: 1_600)
                return imageView
            }
            // Add the pages first: a constraint to the scroll view needs both views in the same hierarchy.
            AppComponents.replaceArrangedSubviews(of: pagesStack, with: pages)
            NSLayoutConstraint.activate(pages.map { $0.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor) })
        }
        placeholder.configure(category: category, caption: photoURLs.isEmpty && !isLoading ? L10n.Explore.noPhotosYet : nil)
        placeholder.isHidden = !photoURLs.isEmpty
        scrollView.isHidden = photoURLs.isEmpty
        updateCounter()
        configure360(panorama)
    }

    private func configure360(_ panorama: Panorama) {
        view360Button.isHidden = panorama == .none
        guard panorama != .none else { return }
        var config = UIButton.Configuration.filled()
        config.title = panorama == .photo ? L10n.Detail.view360 : L10n.Detail.lookAround
        config.image = UIImage(systemName: panorama == .photo ? "rotate.3d" : "binoculars.fill")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .medium)
        config.imagePadding = AppSpacing.xs + 2
        config.cornerStyle = .capsule
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 14)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = AppTypography.captionBold
            return updated
        }
        view360Button.configuration = config
    }

    private func updateCounter() {
        counterChip.isHidden = urls.count < 2
        guard urls.count >= 2 else { return }
        counterChip.configure(symbol: "photo.on.rectangle", text: "\(currentPage + 1) / \(urls.count)")
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0, !urls.isEmpty else { return }
        let page = min(max(Int((scrollView.contentOffset.x / width).rounded()), 0), urls.count - 1)
        guard page != currentPage else { return }
        currentPage = page
        updateCounter()
    }
}
