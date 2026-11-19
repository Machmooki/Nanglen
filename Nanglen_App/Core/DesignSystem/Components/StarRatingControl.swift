import UIKit

/// Star input. Review composer: whole stars 1–5. Filter: optional half stars (`step = 0.5`, tap the left half of a star)
/// and `allowsClearing` (tap the current value again to go back to 0 = "any").
/// Adjustable with VoiceOver (swipe up/down) and labelled per Product Rules.
final class StarRatingControl: UIControl {
    /// Smallest selectable change: 1 = whole stars, 0.5 = half stars.
    var step: Double = 1 { didSet { render() } }
    /// Tapping the selected value again clears it to 0.
    var allowsClearing = false
    /// Caption and accessibility value for a rating; `nil` uses the review composer wording.
    var captionProvider: ((Double) -> String)? { didSet { render() } }
    /// Hides the caption under the stars (when the screen shows the value elsewhere).
    var showsCaption = true { didSet { captionLabel.isHidden = !showsCaption } }

    private(set) var rating: Double = 0
    /// Whole-star value (review composer).
    var value: Int { Int(rating.rounded()) }

    private var starViews: [UIImageView] = []
    private let stack = UIStackView()
    private let captionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        stack.axis = .horizontal
        stack.spacing = AppSpacing.s
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        for star in 1...5 {
            let imageView = UIImageView()
            imageView.tag = star
            imageView.contentMode = .center
            imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title1, scale: .large)
            imageView.adjustsImageSizeForAccessibilityContentSizeCategory = true
            imageView.isAccessibilityElement = false
            starViews.append(imageView)
            stack.addArrangedSubview(imageView)
        }
        captionLabel.apply(AppTypography.subheadlineEmphasized, color: AppColors.textSecondary)
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 0
        let container = UIStackView(arrangedSubviews: [stack, captionLabel])
        container.axis = .vertical
        container.spacing = AppSpacing.xs
        container.translatesAutoresizingMaskIntoConstraints = false
        // Touches go to the control itself (tracking below), not to the stars.
        container.isUserInteractionEnabled = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = L10n.Review.rating
        render()
    }

    func setValue(_ newValue: Int, notify: Bool = false) {
        setRating(Double(newValue), notify: notify)
    }

    func setRating(_ newValue: Double, notify: Bool = false) {
        let stepped = (newValue / step).rounded() * step
        let clamped = max(0, min(5, stepped))
        guard clamped != rating else { return }
        rating = clamped
        render()
        if notify {
            AppComponents.selectionHaptic()
            sendActions(for: .valueChanged)
        }
    }

    // MARK: Touch

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        guard let touch, bounds.contains(touch.location(in: self)) else { return }
        let point = touch.location(in: stack)
        guard let star = starViews.min(by: { abs($0.frame.midX - point.x) < abs($1.frame.midX - point.x) }) else { return }
        var tapped = Double(star.tag)
        let isLeftHalf = effectiveUserInterfaceLayoutDirection == .rightToLeft ? point.x > star.frame.midX : point.x < star.frame.midX
        if step < 1, isLeftHalf { tapped -= 0.5 }
        if allowsClearing, tapped == rating {
            setRating(0, notify: true)
        } else {
            setRating(tapped, notify: true)
        }
    }

    override var isHighlighted: Bool {
        didSet { stack.alpha = isHighlighted ? 0.7 : 1 }
    }

    // MARK: Rendering

    private func render() {
        for star in starViews {
            let position = Double(star.tag)
            let symbol: String
            if rating >= position {
                symbol = "star.fill"
            } else if rating >= position - 0.5 {
                symbol = "star.leadinghalf.filled"
            } else {
                symbol = "star"
            }
            star.image = UIImage(systemName: symbol)
            star.tintColor = rating >= position - 0.5 ? AppColors.warning : AppColors.textTertiary
        }
        let text = captionProvider?(rating) ?? (value == 0 ? L10n.Review.ratingRequired : L10n.Rating.starLabel(value))
        captionLabel.text = text
        accessibilityValue = text
    }

    override func accessibilityIncrement() { setRating(rating + step, notify: true) }
    override func accessibilityDecrement() { setRating(rating - step, notify: true) }
}

/// Small read-only star row ("★★★★☆").
enum StarText {
    static func stars(_ rating: Int) -> String {
        String(repeating: "★", count: max(0, min(5, rating))) + String(repeating: "☆", count: max(0, 5 - rating))
    }
}
