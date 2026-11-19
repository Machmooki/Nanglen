import UIKit

/// Small optional filter sheet (Storyboard scene `FilterViewController`).
final class FilterViewController: UIViewController {
    @IBOutlet private weak var sortTitleLabel: UILabel!
    @IBOutlet private weak var sortControl: UISegmentedControl!
    @IBOutlet private weak var distanceTitleLabel: UILabel!
    @IBOutlet private weak var distanceSlider: StepSlider!
    @IBOutlet private weak var ratingTitleLabel: UILabel!
    @IBOutlet private weak var ratingControl: StarRatingControl!
    @IBOutlet private weak var footnoteLabel: UILabel!
    @IBOutlet private weak var applyButton: UIButton!

    private var viewModel: FilterViewModel?
    private var onApply: ((VenueFilter) -> Void)?
    private let goodForTitle = UILabel()
    private let goodForHint = UILabel()
    private let tagChips = ChipGroupView()
    private let reviewedSwitch = UISwitch()
    private let distanceValueLabel = UILabel()
    private let distanceRangeLabel = UILabel()
    private let haptics = UISelectionFeedbackGenerator()
    private var lastHapticDistance: Double?

    func configure(viewModel: FilterViewModel, onApply: @escaping (VenueFilter) -> Void) {
        self.viewModel = viewModel
        self.onApply = onApply
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        title = L10n.Filter.title
        navigationItem.leftBarButtonItem?.title = L10n.Filter.reset
        [sortTitleLabel, distanceTitleLabel, ratingTitleLabel].forEach { AppStyles.sectionTitle($0) }
        sortTitleLabel.text = L10n.Filter.sort
        distanceTitleLabel.text = L10n.Filter.distance
        ratingTitleLabel.text = L10n.Filter.minimumRating
        footnoteLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        footnoteLabel.text = L10n.Filter.footnote
        fill(sortControl, FilterViewModel.sorts.map(FilterViewModel.title(for:)))
        setUpDistance()
        setUpRating()
        AppStyles.primaryButton(applyButton, title: L10n.Filter.apply)
        addGoodForSection()
        viewModel?.onChange = { [weak self] _ in self?.render() }
        render()
    }

    /// "Good for" chips and the reviews switch go first: they are the filters people use most.
    private func addGoodForSection() {
        guard let stack = sortTitleLabel.superview as? UIStackView else { return }
        AppStyles.sectionTitle(goodForTitle)
        goodForTitle.text = L10n.Filter.goodFor
        goodForHint.apply(AppTypography.footnote, color: AppColors.textSecondary)
        let tagLimit = viewModel?.limits.tagSelectionLimit
        goodForHint.text = tagLimit.map(L10n.Filter.goodForHint) ?? L10n.Filter.goodForHintAny
        goodForHint.numberOfLines = 0
        tagChips.maximumSelection = tagLimit
        tagChips.configure(items: VenueFilter.goodForTags.compactMap(ReviewTag.named).map { .init(id: $0.slug, title: $0.title, symbol: $0.symbol) },
                           selection: viewModel?.filter.tags ?? [])
        tagChips.onChange = { [weak self] selection in self?.viewModel?.setTags(selection) }
        tagChips.onLimitReached = { [weak self] in self?.showToast(L10n.Filter.tooManyTags(tagLimit ?? 0)) }

        let switchLabel = UILabel()
        switchLabel.apply(AppTypography.body)
        switchLabel.text = L10n.Filter.reviewedOnly
        switchLabel.numberOfLines = 0
        reviewedSwitch.onTintColor = AppColors.primary
        reviewedSwitch.accessibilityLabel = L10n.Filter.reviewedOnly
        reviewedSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            viewModel?.setReviewedOnly(reviewedSwitch.isOn)
        }, for: .valueChanged)
        let switchRow = UIStackView(arrangedSubviews: [switchLabel, reviewedSwitch])
        switchRow.alignment = .center
        switchRow.spacing = AppSpacing.m

        for (offset, view) in [goodForTitle, goodForHint, tagChips, switchRow].enumerated() {
            stack.insertArrangedSubview(view, at: offset)
        }
        stack.setCustomSpacing(AppSpacing.xs, after: goodForTitle)
        stack.setCustomSpacing(AppSpacing.xxl, after: switchRow)
    }

    /// Continuous slider with a live "Within 2.5 km" label; snaps to the configured step on release.
    private func setUpDistance() {
        guard let viewModel, let stack = distanceTitleLabel.superview as? UIStackView else { return }
        let limits = viewModel.limits
        distanceSlider.minimumValue = Float(limits.distanceMinMeters)
        distanceSlider.maximumValue = Float(limits.distanceMaxMeters)
        distanceSlider.step = Float(limits.distanceStepMeters)
        distanceSlider.minimumTrackTintColor = AppColors.primary
        distanceSlider.isContinuous = true
        distanceSlider.accessibilityLabel = L10n.Filter.distance
        distanceSlider.accessibilityHint = L10n.Filter.distanceHint
        distanceSlider.formatValue = { FilterViewModel.distanceText(Double($0)) }

        distanceValueLabel.apply(AppTypography.subheadlineEmphasized, color: AppColors.primary)
        distanceValueLabel.textAlignment = .natural
        distanceValueLabel.numberOfLines = 0
        distanceValueLabel.isAccessibilityElement = false // the slider announces the value
        distanceRangeLabel.apply(AppTypography.caption, color: AppColors.textTertiary)
        distanceRangeLabel.numberOfLines = 0
        distanceRangeLabel.text = FilterViewModel.distanceText(limits.distanceMinMeters) + " – " + FilterViewModel.distanceText(limits.distanceMaxMeters)
        distanceRangeLabel.isAccessibilityElement = false
        if let titleIndex = stack.arrangedSubviews.firstIndex(of: distanceTitleLabel) {
            stack.insertArrangedSubview(distanceValueLabel, at: titleIndex + 1)
            stack.setCustomSpacing(AppSpacing.xs, after: distanceTitleLabel)
        }
        if let sliderIndex = stack.arrangedSubviews.firstIndex(of: distanceSlider) {
            stack.insertArrangedSubview(distanceRangeLabel, at: sliderIndex + 1)
            stack.setCustomSpacing(AppSpacing.xs, after: distanceSlider)
        }
    }

    private func setUpRating() {
        guard let viewModel else { return }
        ratingControl.step = viewModel.limits.ratingStep
        ratingControl.allowsClearing = true
        ratingControl.captionProvider = { FilterViewModel.ratingText($0 > 0 ? $0 : nil) }
        ratingControl.accessibilityLabel = L10n.Filter.minimumRating
        ratingControl.accessibilityHint = L10n.Filter.ratingClearHint
    }

    private func fill(_ control: UISegmentedControl, _ titles: [String]) {
        control.removeAllSegments()
        for (index, title) in titles.enumerated() { control.insertSegment(withTitle: title, at: index, animated: false) }
        AppStyles.segmentedControl(control)
    }

    private func render() {
        guard let filter = viewModel?.filter else { return }
        sortControl.selectedSegmentIndex = FilterViewModel.sorts.firstIndex(of: filter.sort) ?? 0
        if !distanceSlider.isTracking { distanceSlider.setValue(Float(filter.distanceMeters), animated: false) }
        distanceValueLabel.text = L10n.Filter.within(FilterViewModel.distanceText(filter.distanceMeters))
        distanceSlider.updateAccessibilityValue()
        if ratingControl.rating != (filter.minimumRating ?? 0) { ratingControl.setRating(filter.minimumRating ?? 0) }
        if reviewedSwitch.isOn != filter.reviewedOnly { reviewedSwitch.setOn(filter.reviewedOnly, animated: true) }
        if tagChips.selection != filter.tags {
            tagChips.configure(items: VenueFilter.goodForTags.compactMap(ReviewTag.named).map { .init(id: $0.slug, title: $0.title, symbol: $0.symbol) },
                               selection: filter.tags)
        }
    }

    @IBAction private func sortChanged(_ sender: UISegmentedControl) { viewModel?.setSort(index: sender.selectedSegmentIndex) }
    /// Live while dragging: the label follows the snapped value, with a light tick each time a step is crossed.
    @IBAction private func distanceChanged(_ sender: UISlider) {
        guard let viewModel else { return }
        let snapped = viewModel.limits.snappedDistance(Double(sender.value))
        if snapped != lastHapticDistance {
            if lastHapticDistance != nil { haptics.selectionChanged() }
            lastHapticDistance = snapped
            haptics.prepare()
        }
        viewModel.setDistance(snapped)
    }

    /// Snap the thumb onto the step when the finger lifts.
    @IBAction private func distanceReleased(_ sender: UISlider) {
        guard let viewModel else { return }
        viewModel.setDistance(Double(sender.value))
        sender.setValue(Float(viewModel.filter.distanceMeters), animated: true)
        lastHapticDistance = nil
    }

    @IBAction private func ratingChanged(_ sender: StarRatingControl) {
        viewModel?.setMinimumRating(sender.rating > 0 ? sender.rating : nil)
    }
    @IBAction private func resetTapped(_ sender: Any) { viewModel?.reset() }
    @IBAction private func closeTapped(_ sender: Any) { dismiss(animated: true) }

    @IBAction private func applyTapped(_ sender: UIButton) {
        if let filter = viewModel?.filter { onApply?(filter) }
        AppComponents.selectionHaptic()
        dismiss(animated: true)
    }
}

/// Slider that moves by `step` with VoiceOver (swipe up/down) and announces a formatted value instead of a percentage.
final class StepSlider: UISlider {
    var step: Float = 1
    var formatValue: ((Float) -> String)?

    override func accessibilityIncrement() { adjust(by: step) }
    override func accessibilityDecrement() { adjust(by: -step) }

    func updateAccessibilityValue() {
        accessibilityValue = formatValue?(value)
    }

    private func adjust(by delta: Float) {
        let stepped = ((value + delta - minimumValue) / max(step, 1)).rounded() * max(step, 1) + minimumValue
        setValue(min(max(stepped, minimumValue), maximumValue), animated: true)
        sendActions(for: .valueChanged)
        sendActions(for: .touchUpInside)
        updateAccessibilityValue()
    }
}
