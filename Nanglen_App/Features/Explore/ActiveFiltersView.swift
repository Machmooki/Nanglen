import UIKit

/// Shows each active filter as a removable chip ("Quiet ✕", "4★ & up ✕") plus "Clear all",
/// so people always see why results changed and can undo any filter with one tap.
final class ActiveFiltersView: UIView {
    var onRemove: ((VenueFilter.Item) -> Void)?
    var onClearAll: (() -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
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
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: AppSpacing.screenMargin),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -AppSpacing.screenMargin),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(filter: VenueFilter) {
        let chips: [UIView] = filter.activeItems.map { item in
            let title = FilterViewModel.title(for: item, in: filter)
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = title
            config.image = UIImage(systemName: "xmark")
            config.imagePlacement = .trailing
            config.imagePadding = AppSpacing.xs
            config.cornerStyle = .capsule
            config.buttonSize = .small
            config.baseBackgroundColor = AppColors.primarySoft
            config.baseForegroundColor = AppColors.primary
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .caption2, scale: .small)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = AppTypography.captionBold
                return updated
            }
            button.configuration = config
            button.accessibilityLabel = L10n.Filter.removeFilter(title)
            button.addAction(UIAction { [weak self] _ in
                AppComponents.selectionHaptic()
                self?.onRemove?(item)
            }, for: .primaryActionTriggered)
            return button
        }
        var views = chips
        if chips.count > 1 {
            let clear = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.title = L10n.Filter.clearAll
            config.buttonSize = .small
            config.baseForegroundColor = AppColors.textSecondary
            clear.configuration = config
            clear.addAction(UIAction { [weak self] _ in self?.onClearAll?() }, for: .primaryActionTriggered)
            views.append(clear)
        }
        AppComponents.replaceArrangedSubviews(of: stack, with: views)
        isHidden = chips.isEmpty
    }
}
