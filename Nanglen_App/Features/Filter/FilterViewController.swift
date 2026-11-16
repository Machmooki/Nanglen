import UIKit

/// Small optional filter sheet (Storyboard scene `FilterViewController`).
final class FilterViewController: UIViewController {
    @IBOutlet private weak var sortTitleLabel: UILabel!
    @IBOutlet private weak var sortControl: UISegmentedControl!
    @IBOutlet private weak var distanceTitleLabel: UILabel!
    @IBOutlet private weak var distanceControl: UISegmentedControl!
    @IBOutlet private weak var ratingTitleLabel: UILabel!
    @IBOutlet private weak var ratingControl: UISegmentedControl!
    @IBOutlet private weak var footnoteLabel: UILabel!
    @IBOutlet private weak var applyButton: UIButton!

    private var viewModel: FilterViewModel?
    private var onApply: ((VenueFilter) -> Void)?
    private let goodForTitle = UILabel()
    private let goodForHint = UILabel()
    private let tagChips = ChipGroupView()
    private let reviewedSwitch = UISwitch()

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
        fill(distanceControl, FilterViewModel.distances.map(FilterViewModel.title(for:)))
        fill(ratingControl, FilterViewModel.ratings.map(FilterViewModel.title(for:)))
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
        goodForHint.text = L10n.Filter.goodForHint
        goodForHint.numberOfLines = 0
        tagChips.maximumSelection = VenueFilter.maxTags
        tagChips.configure(items: VenueFilter.goodForTags.compactMap(ReviewTag.named).map { .init(id: $0.slug, title: $0.title, symbol: $0.symbol) },
                           selection: viewModel?.filter.tags ?? [])
        tagChips.onChange = { [weak self] selection in self?.viewModel?.setTags(selection) }
        tagChips.onLimitReached = { [weak self] in self?.showToast(L10n.Filter.tooManyTags) }

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

    private func fill(_ control: UISegmentedControl, _ titles: [String]) {
        control.removeAllSegments()
        for (index, title) in titles.enumerated() { control.insertSegment(withTitle: title, at: index, animated: false) }
        AppStyles.segmentedControl(control)
    }

    private func render() {
        guard let filter = viewModel?.filter else { return }
        sortControl.selectedSegmentIndex = FilterViewModel.sorts.firstIndex(of: filter.sort) ?? 0
        distanceControl.selectedSegmentIndex = FilterViewModel.distances.firstIndex(of: filter.distance) ?? 1
        ratingControl.selectedSegmentIndex = FilterViewModel.ratings.firstIndex(of: filter.minimumRating) ?? 0
        if reviewedSwitch.isOn != filter.reviewedOnly { reviewedSwitch.setOn(filter.reviewedOnly, animated: true) }
        if tagChips.selection != filter.tags {
            tagChips.configure(items: VenueFilter.goodForTags.compactMap(ReviewTag.named).map { .init(id: $0.slug, title: $0.title, symbol: $0.symbol) },
                               selection: filter.tags)
        }
    }

    @IBAction private func sortChanged(_ sender: UISegmentedControl) { viewModel?.setSort(index: sender.selectedSegmentIndex) }
    @IBAction private func distanceChanged(_ sender: UISegmentedControl) { viewModel?.setDistance(index: sender.selectedSegmentIndex) }
    @IBAction private func ratingChanged(_ sender: UISegmentedControl) { viewModel?.setRating(index: sender.selectedSegmentIndex) }
    @IBAction private func resetTapped(_ sender: Any) { viewModel?.reset() }
    @IBAction private func closeTapped(_ sender: Any) { dismiss(animated: true) }

    @IBAction private func applyTapped(_ sender: UIButton) {
        if let filter = viewModel?.filter { onApply?(filter) }
        AppComponents.selectionHaptic()
        dismiss(animated: true)
    }
}
