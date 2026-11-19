import UIKit
import UniformTypeIdentifiers

/// Horizontal row of photo thumbnails (new local picks and/or photos already uploaded) plus an "add" tile.
final class PhotoStripView: UIView {
    enum Item: Equatable {
        /// Picked on this device, not uploaded yet.
        case local(UIImage)
        /// Already on the server (signed URL; `nil` while it is being resolved).
        case remote(URL?)
    }

    var maximumCount = 5 { didSet { if maximumCount != oldValue { render() } } }
    var onAdd: (() -> Void)?
    var onRemove: ((Int) -> Void)?
    private(set) var items: [Item] = []
    /// The "add" tile, e.g. to anchor an action sheet.
    private(set) var addButton: UIView?
    private let stack = UIStackView()
    private let scroll = UIScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = AppSpacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 84),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        render()
    }

    /// Room left for new photos.
    var remainingCount: Int { max(0, maximumCount - items.count) }

    func setImages(_ images: [UIImage]) {
        setItems(images.map(Item.local))
    }

    func setItems(_ items: [Item]) {
        guard items != self.items else { return }
        self.items = items
        render()
    }

    private func render() {
        var views: [UIView] = items.enumerated().map { index, item in
            let container = UIView()
            let imageView: UIImageView
            switch item {
            case .local(let image):
                imageView = UIImageView(image: image)
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.layer.cornerRadius = AppRadius.small
            case .remote(let url):
                let remote = RemoteImageView()
                remote.load(url, maxPixelSize: 252)
                imageView = remote
            }
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.isAccessibilityElement = true
            imageView.accessibilityTraits = .image
            imageView.accessibilityLabel = L10n.Detail.photoPosition(index + 1, items.count)
            let remove = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "xmark.circle.fill")
            config.baseForegroundColor = .white
            remove.configuration = config
            remove.layer.shadowColor = UIColor.black.cgColor
            remove.layer.shadowOpacity = 0.35
            remove.layer.shadowRadius = 2
            remove.layer.shadowOffset = .zero
            remove.accessibilityLabel = L10n.Common.remove + ", " + L10n.Detail.photoPosition(index + 1, items.count)
            remove.addAction(UIAction { [weak self] _ in self?.onRemove?(index) }, for: .primaryActionTriggered)
            remove.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(imageView)
            container.addSubview(remove)
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: 84),
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                remove.topAnchor.constraint(equalTo: container.topAnchor),
                remove.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
            return container
        }
        addButton = nil
        if items.count < maximumCount {
            let add = UIButton(type: .system)
            var config = UIButton.Configuration.gray()
            config.image = UIImage(systemName: "camera.fill")
            config.title = L10n.Review.addPhoto
            config.subtitle = "\(items.count)/\(maximumCount)"
            config.imagePlacement = .top
            config.imagePadding = AppSpacing.xs
            config.titleAlignment = .center
            config.baseForegroundColor = AppColors.primary
            config.background.cornerRadius = AppRadius.small
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = AppTypography.caption
                return updated
            }
            config.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = AppTypography.caption
                updated.foregroundColor = AppColors.textSecondary
                return updated
            }
            add.configuration = config
            add.accessibilityLabel = L10n.Review.addPhoto
            add.accessibilityValue = "\(items.count)/\(maximumCount)"
            add.addAction(UIAction { [weak self] _ in self?.onAdd?() }, for: .primaryActionTriggered)
            add.widthAnchor.constraint(equalToConstant: 84).isActive = true
            views.append(add)
            addButton = add
        }
        AppComponents.replaceArrangedSubviews(of: stack, with: views)
    }
}

/// Re-encodes picked images to JPEG under the upload limit (MIME/size enforced again by the server).
enum PhotoEncoder {
    static func upload(from image: UIImage, maxBytes: Int = 5 * 1_024 * 1_024, maxDimension: CGFloat = 2_048) -> PhotoUpload? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        var quality: CGFloat = 0.8
        while quality >= 0.3 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return PhotoUpload(data: data, mimeType: UTType.jpeg.preferredMIMEType ?? "image/jpeg", fileExtension: "jpg",
                                   width: Int(size.width), height: Int(size.height))
            }
            quality -= 0.15
        }
        return nil
    }
}
