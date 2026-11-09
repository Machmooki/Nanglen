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
        viewModel?.onChange = { [weak self] _ in self?.render() }
        render()
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
