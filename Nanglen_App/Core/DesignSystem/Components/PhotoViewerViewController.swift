import UIKit

/// Full-screen, swipeable photo viewer (review photos). Same paging pattern as `VenueHeroGalleryView`,
/// with aspect-fit pages, double-tap / pinch to zoom, a counter and a close button.
final class PhotoViewerViewController: UIViewController, UIScrollViewDelegate {
    private let urls: [URL]
    private let startIndex: Int
    private let pager = UIScrollView()
    private let pagesStack = UIStackView()
    private let counterChip = OverlayChipView(style: .dark)
    private let closeButton = UIButton(type: .system)
    private var zoomViews: [ZoomingImageView] = []
    private var currentPage = 0

    init(urls: [URL], startIndex: Int = 0) {
        self.urls = urls
        self.startIndex = min(max(startIndex, 0), max(urls.count - 1, 0))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.delegate = self
        pagesStack.axis = .horizontal
        [pager, counterChip, closeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        pagesStack.translatesAutoresizingMaskIntoConstraints = false
        pager.addSubview(pagesStack)

        zoomViews = urls.enumerated().map { index, url in
            let page = ZoomingImageView()
            page.load(url)
            page.isAccessibilityElement = true
            page.accessibilityTraits = .image
            page.accessibilityLabel = L10n.Detail.photoPosition(index + 1, urls.count)
            return page
        }
        zoomViews.forEach(pagesStack.addArrangedSubview)

        var close = UIButton.Configuration.filled()
        close.image = UIImage(systemName: "xmark")
        close.cornerStyle = .capsule
        close.baseBackgroundColor = UIColor.white.withAlphaComponent(0.2)
        close.baseForegroundColor = .white
        closeButton.configuration = close
        closeButton.accessibilityLabel = L10n.Common.close
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)

        NSLayoutConstraint.activate([
            pager.topAnchor.constraint(equalTo: view.topAnchor),
            pager.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pager.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pagesStack.topAnchor.constraint(equalTo: pager.contentLayoutGuide.topAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: pager.contentLayoutGuide.bottomAnchor),
            pagesStack.leadingAnchor.constraint(equalTo: pager.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: pager.contentLayoutGuide.trailingAnchor),
            pagesStack.heightAnchor.constraint(equalTo: pager.frameLayoutGuide.heightAnchor),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AppSpacing.s),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -AppSpacing.l),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            counterChip.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            counterChip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -AppSpacing.l),
        ] + zoomViews.map { $0.widthAnchor.constraint(equalTo: pager.frameLayoutGuide.widthAnchor) })

        // Swipe down to close, like Photos.
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        swipe.direction = .down
        view.addGestureRecognizer(swipe)
        currentPage = startIndex
        updateCounter()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Jump to the tapped photo once the pages have a size.
        let target = CGFloat(currentPage) * pager.bounds.width
        if pager.bounds.width > 0, abs(pager.contentOffset.x - target) > 1, !pager.isDragging, !pager.isDecelerating {
            pager.contentOffset = CGPoint(x: target, y: 0)
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        dismiss(animated: true)
        return true
    }

    @objc private func swipedDown() {
        guard zoomViews[safe: currentPage]?.isZoomed != true else { return }
        dismiss(animated: true)
    }

    private func updateCounter() {
        counterChip.isHidden = urls.count < 2
        counterChip.configure(symbol: "photo.on.rectangle", text: L10n.PhotoSource.viewerTitle(currentPage + 1, urls.count))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0, !urls.isEmpty else { return }
        let page = min(max(Int((scrollView.contentOffset.x / width).rounded()), 0), urls.count - 1)
        guard page != currentPage else { return }
        zoomViews[safe: currentPage]?.resetZoom()
        currentPage = page
        updateCounter()
    }
}

/// One zoomable, aspect-fit page.
private final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView = RemoteImageView()

    var isZoomed: Bool { zoomScale > minimumZoomScale + 0.01 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.layer.cornerRadius = 0
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            imageView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
        ])
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func load(_ url: URL) { imageView.load(url, maxPixelSize: 2_048) }

    func resetZoom() { setZoomScale(minimumZoomScale, animated: false) }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if isZoomed {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
