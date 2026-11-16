import UIKit

/// Lays out arranged views left-to-right and wraps to new lines (like tags or chips).
/// Works inside stack views and Storyboards: height follows the content for the current width.
class WrapLayoutView: UIView {
    var spacing: CGFloat = AppSpacing.s { didSet { setNeedsLayout() } }
    var lineSpacing: CGFloat = AppSpacing.s { didSet { setNeedsLayout() } }
    private(set) var arrangedViews: [UIView] = []
    private var lastWidth: CGFloat = 0
    private var contentHeight: CGFloat = 0

    func setArrangedViews(_ views: [UIView]) {
        arrangedViews.forEach { $0.removeFromSuperview() }
        arrangedViews = views
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            addSubview($0)
        }
        lastWidth = 0
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    /// Cached measurement so Auto Layout's repeated size queries don't re-measure every subview.
    private var measuredCache: (width: CGFloat, height: CGFloat)?

    override var intrinsicContentSize: CGSize {
        guard !arrangedViews.isEmpty else { return CGSize(width: UIView.noIntrinsicMetric, height: 0) }
        let width = bounds.width > 0 ? bounds.width : 320
        if width == lastWidth, contentHeight > 0 {
            return CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
        }
        if let cache = measuredCache, cache.width == width {
            return CGSize(width: UIView.noIntrinsicMetric, height: cache.height)
        }
        let height = measuredHeight(for: width)
        measuredCache = (width, height)
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func setNeedsLayout() {
        measuredCache = nil
        super.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = layout(width: bounds.width, apply: true)
        if bounds.width != lastWidth || height != contentHeight {
            lastWidth = bounds.width
            contentHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        observeTextSize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeTextSize()
    }

    private func observeTextSize() {
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: WrapLayoutView, _: UITraitCollection) in
            view.lastWidth = 0
            view.setNeedsLayout()
            view.invalidateIntrinsicContentSize()
        }
    }

    private func measuredHeight(for width: CGFloat) -> CGFloat {
        layout(width: width > 0 ? width : 320, apply: false)
    }

    @discardableResult
    private func layout(width: CGFloat, apply: Bool) -> CGFloat {
        guard width > 0 else { return 0 }
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in arrangedViews where !view.isHidden {
            var size = view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            size.width = min(size.width, width)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            if apply {
                let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
                let originX = isRTL ? width - x - size.width : x
                view.frame = CGRect(x: originX, y: y, width: size.width, height: size.height)
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return y + lineHeight
    }
}

/// Selectable capsule chips with an optional maximum number of selections.
final class ChipGroupView: WrapLayoutView {
    struct Item: Hashable {
        var id: String
        var title: String
        var symbol: String?
    }

    var allowsMultipleSelection = true
    var maximumSelection: Int?
    var onChange: ((Set<String>) -> Void)?
    /// Called when the user tries to exceed `maximumSelection`.
    var onLimitReached: (() -> Void)?
    private(set) var selection: Set<String> = []
    private var buttons: [String: UIButton] = [:]

    func configure(items: [Item], selection: Set<String>) {
        self.selection = selection
        buttons = [:]
        let views = items.map { item -> UIButton in
            let button = UIButton(type: .system)
            button.addAction(UIAction { [weak self] _ in self?.toggle(item.id) }, for: .primaryActionTriggered)
            button.accessibilityLabel = item.title
            buttons[item.id] = button
            apply(item: item, to: button)
            return button
        }
        setArrangedViews(views)
        refreshAppearance(items: items)
    }

    private var items: [Item] = []

    private func refreshAppearance(items: [Item]) {
        self.items = items
        for item in items {
            if let button = buttons[item.id] { apply(item: item, to: button) }
        }
    }

    private func apply(item: Item, to button: UIButton) {
        let isSelected = selection.contains(item.id)
        var config = isSelected ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        config.title = item.title
        config.image = item.symbol.flatMap { UIImage(systemName: $0) }
        config.imagePadding = AppSpacing.xs
        config.cornerStyle = .capsule
        config.buttonSize = .small
        config.baseBackgroundColor = isSelected ? AppColors.primary : AppColors.card
        config.baseForegroundColor = isSelected ? .white : AppColors.textPrimary
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .footnote)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = AppTypography.chip
            return updated
        }
        button.configuration = config
        button.accessibilityTraits = isSelected ? [.button, .selected] : .button
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else if !allowsMultipleSelection {
            selection = [id]
        } else if let maximumSelection, selection.count >= maximumSelection {
            onLimitReached?()
            return
        } else {
            selection.insert(id)
        }
        AppComponents.selectionHaptic()
        refreshAppearance(items: items)
        setNeedsLayout()
        onChange?(selection)
    }
}

/// Read-only wrapping row of community tag pills.
final class TagPillsView: WrapLayoutView {
    func configure(_ models: [StatusPillModel]) {
        setArrangedViews(models.map { model in
            let pill = StatusPillView()
            pill.configure(model)
            return pill
        })
    }
}
