import MapKit
import UIKit

/// Search-first discovery screen. Layout lives in Main.storyboard; this class
/// only renders `ExploreViewModel.State` and forwards user input.
final class ExploreViewController: UIViewController, AppContainerConfigurable {
    private enum Segue {
        static let showVenueDetail = "showVenueDetail"
        static let presentFilter = "presentFilter"
        static let presentAddPlace = "presentAddPlace"
    }

    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var loadingIndicator: UIActivityIndicatorView!
    @IBOutlet private weak var viewModeControl: UISegmentedControl!
    @IBOutlet private weak var locationButton: UIButton!
    @IBOutlet private weak var searchBar: UISearchBar!
    @IBOutlet private weak var filterButton: UIButton!
    @IBOutlet private weak var filterBadgeLabel: UILabel!
    @IBOutlet private weak var categoryCollectionView: UICollectionView!
    @IBOutlet private weak var bannerView: UIView!
    @IBOutlet private weak var bannerCardView: UIView!
    @IBOutlet private weak var bannerLabel: UILabel!
    @IBOutlet private weak var tableView: UITableView!
    @IBOutlet private weak var mapView: MKMapView!
    @IBOutlet private weak var searchAreaButton: UIButton!
    @IBOutlet private weak var locateButton: UIButton!

    private var container: AppContainer?
    private var viewModel: ExploreViewModel?
    private var dataSource: ExploreDataSource?
    private var mapController: ExploreMapController?
    private let emptyStateView = EmptyStateView()
    private let categories: [VenueCategory?] = [nil, .cafe, .library, .coworking, .studySpace, .other]
    private var pendingDetail: VenueSummary?
    private let footerView = ExploreFooterView()
    private let activeFiltersView = ActiveFiltersView()
    private var renderedFilter: VenueFilter?
    private let eyebrowLabel = UILabel()
    private let addPlaceButton = UIButton(type: .system)
    private var addPlaceBottom: NSLayoutConstraint?

    func configure(with container: AppContainer) {
        self.container = container
        viewModel = container.makeExploreViewModel()
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let viewModel else {
            assertionFailure("ExploreViewController needs configure(with:) before loading")
            return
        }
        setUpAppearance()
        setUpList()
        setUpMap()
        setUpCategories()
        bind(viewModel)
        viewModel.start()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        if let selected = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selected, animated: animated)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // MARK: Setup

    private func setUpAppearance() {
        view.backgroundColor = AppColors.background
        navigationItem.backButtonDisplayMode = .minimal
        titleLabel.apply(AppTypography.largeTitle)
        titleLabel.text = L10n.Explore.title
        titleLabel.accessibilityTraits = .header
        loadingIndicator.color = AppColors.primary
        setUpEyebrow()

        viewModeControl.setImage(UIImage(systemName: "list.bullet"), forSegmentAt: 0)
        viewModeControl.setImage(UIImage(systemName: "map"), forSegmentAt: 1)
        viewModeControl.selectedSegmentTintColor = AppColors.primary
        viewModeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        viewModeControl.accessibilityLabel = "\(L10n.Explore.viewList) / \(L10n.Explore.viewMap)"

        searchBar.placeholder = L10n.Explore.searchPlaceholder
        searchBar.searchBarStyle = .minimal
        searchBar.returnKeyType = .search
        searchBar.searchTextField.font = AppTypography.body
        searchBar.searchTextField.backgroundColor = AppColors.card
        searchBar.delegate = self

        var filterConfig = UIButton.Configuration.glass()
        filterConfig.image = UIImage(systemName: "slider.horizontal.3")
        filterConfig.baseForegroundColor = AppColors.primary
        filterConfig.cornerStyle = .capsule
        filterButton.configuration = filterConfig
        filterButton.accessibilityLabel = L10n.Explore.filter

        filterBadgeLabel.apply(AppTypography.captionBold, color: .white)
        filterBadgeLabel.backgroundColor = AppColors.primary
        filterBadgeLabel.layer.cornerRadius = 9
        filterBadgeLabel.layer.masksToBounds = true
        filterBadgeLabel.textAlignment = .center
        filterBadgeLabel.isHidden = true

        AppStyles.card(bannerCardView, radius: AppRadius.control)
        bannerCardView.backgroundColor = StatusTone.warning.background
        bannerLabel.apply(AppTypography.footnote, color: AppColors.warning)

        AppStyles.overlayButton(searchAreaButton, title: L10n.Explore.searchThisArea, systemImage: "arrow.clockwise")
        AppStyles.overlayButton(locateButton, title: nil, systemImage: "location.fill")
        locateButton.accessibilityLabel = L10n.Explore.locateMe
        searchAreaButton.isHidden = true
        setUpAddPlaceButton()
    }

    /// Round glass "+" floating above the list (and above the locate button in map mode).
    private func setUpAddPlaceButton() {
        var config = UIButton.Configuration.prominentGlass()
        config.image = UIImage(systemName: "plus")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        config.baseBackgroundColor = AppColors.primary
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        addPlaceButton.configuration = config
        addPlaceButton.accessibilityLabel = L10n.Explore.addPlace
        addPlaceButton.accessibilityIdentifier = "explore.addPlace"
        addPlaceButton.addAction(UIAction { [weak self] _ in
            AppComponents.selectionHaptic()
            self?.showAddPlace()
        }, for: .primaryActionTriggered)
        addPlaceButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addPlaceButton)
        let bottom = addPlaceButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -AppSpacing.l)
        addPlaceBottom = bottom
        NSLayoutConstraint.activate([
            addPlaceButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -AppSpacing.l),
            addPlaceButton.widthAnchor.constraint(equalToConstant: 60),
            addPlaceButton.heightAnchor.constraint(equalToConstant: 60),
            bottom,
        ])
    }

    private func setUpList() {
        tableView.register(ExplorePlaceCardCell.self, forCellReuseIdentifier: ExplorePlaceCardCell.reuseIdentifier)
        tableView.estimatedRowHeight = 320
        tableView.register(SectionHeaderView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderView.reuseIdentifier)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
        // Room for the floating Add Place button so it never covers the last card.
        tableView.contentInset.bottom = AppSpacing.l + 72
        tableView.keyboardDismissMode = .onDrag
        tableView.delegate = self
        dataSource = ExploreDataSource(tableView: tableView)
        emptyStateView.onAction = { [weak self] in self?.handleEmptyStateAction() }
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            self?.viewModel?.retry()
            refresh?.endRefreshing()
        }, for: .valueChanged)
        tableView.refreshControl = refresh
        footerView.onAddPlace = { [weak self] in self?.showAddPlace() }
        footerView.onLoadMore = { [weak self] in self?.viewModel?.loadMore() }
    }

    /// Small friendly line above the big title ("Find your chill spot ✨").
    private func setUpEyebrow() {
        guard let header = categoryCollectionView.superview as? UIStackView else { return }
        eyebrowLabel.apply(AppTypography.captionBold, color: AppColors.primary)
        eyebrowLabel.text = L10n.Explore.eyebrow
        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = UIView()
        wrapper.addSubview(eyebrowLabel)
        NSLayoutConstraint.activate([
            eyebrowLabel.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: AppSpacing.xs),
            eyebrowLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            eyebrowLabel.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: AppSpacing.screenMargin),
            eyebrowLabel.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -AppSpacing.screenMargin),
        ])
        header.insertArrangedSubview(wrapper, at: 0)
        header.setCustomSpacing(0, after: wrapper)
    }

    private func setUpMap() {
        let controller = ExploreMapController(mapView: mapView)
        controller.onSelect = { [weak self] item in self?.showDetail(for: item.venue) }
        controller.onUserMovedMap = { [weak self] _ in
            guard let self, searchAreaButton.isHidden else { return }
            searchAreaButton.alpha = 0
            searchAreaButton.isHidden = false
            UIView.animate(withDuration: 0.25) { self.searchAreaButton.alpha = 1 }
        }
        mapController = controller
        mapView.isHidden = true
        locateButton.isHidden = true
    }

    private func setUpCategories() {
        categoryCollectionView.dataSource = self
        categoryCollectionView.delegate = self
        categoryCollectionView.allowsMultipleSelection = false
        categoryCollectionView.showsHorizontalScrollIndicator = false
        if let layout = categoryCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
            layout.sectionInset = UIEdgeInsets(top: 0, left: AppSpacing.screenMargin, bottom: 0, right: AppSpacing.screenMargin)
        }
        categoryCollectionView.reloadData()
        categoryCollectionView.selectItem(at: IndexPath(item: 0, section: 0), animated: false, scrollPosition: [])
        if let header = categoryCollectionView.superview as? UIStackView,
           let index = header.arrangedSubviews.firstIndex(of: categoryCollectionView) {
            header.insertArrangedSubview(activeFiltersView, at: index + 1)
        }
        activeFiltersView.isHidden = true
        activeFiltersView.onRemove = { [weak self] item in self?.viewModel?.removeFilter(item) }
        activeFiltersView.onClearAll = { [weak self] in self?.viewModel?.apply(.default) }
    }

    private func bind(_ viewModel: ExploreViewModel) {
        viewModel.onStateChange = { [weak self] state in self?.render(state) }
        viewModel.onEvent = { [weak self] event in self?.handle(event) }
        render(viewModel.state)
    }

    // MARK: Rendering

    private func render(_ state: ExploreViewModel.State) {
        if state.isLoading { loadingIndicator.startAnimating() } else { loadingIndicator.stopAnimating() }

        // Location as a soft capsule "pill" — reads as tappable without shouting.
        var locationConfig = UIButton.Configuration.filled()
        locationConfig.title = state.locationState.text
        locationConfig.image = UIImage(systemName: state.locationState.symbol)
        locationConfig.imagePadding = AppSpacing.xs + 2
        locationConfig.cornerStyle = .capsule
        locationConfig.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 14)
        locationConfig.baseBackgroundColor = state.locationState == .denied ? AppColors.fill : AppColors.primarySoft
        locationConfig.baseForegroundColor = state.locationState == .denied ? AppColors.textSecondary : AppColors.primary
        locationConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .footnote)
        locationConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = AppTypography.subheadlineEmphasized
            return updated
        }
        locationButton.configuration = locationConfig

        let count = state.filter.activeCount
        filterBadgeLabel.text = "\(count)"
        filterBadgeLabel.isHidden = count == 0
        filterButton.accessibilityValue = count == 0 ? nil : "\(count)"
        if renderedFilter != state.filter {
            renderedFilter = state.filter
            activeFiltersView.configure(filter: state.filter)
        }

        bannerLabel.text = state.bannerText
        if bannerView.isHidden != (state.bannerText == nil) {
            UIView.animate(withDuration: 0.2) { self.bannerView.isHidden = state.bannerText == nil }
        }

        dataSource?.apply(state.sections, animated: view.window != nil)
        renderEmptyState(state)
        renderFooter(state)
        mapController?.update(items: state.items)
        syncCategorySelection(with: state.category)
    }

    private func renderEmptyState(_ state: ExploreViewModel.State) {
        guard state.isEmpty else {
            tableView.backgroundView = nil
            return
        }
        let model: EmptyStateView.Model
        if state.isLoading || !state.hasLoadedOnce {
            model = .init(symbol: nil, title: L10n.Explore.searching, message: nil, actionTitle: nil, isLoading: true)
        } else if let error = state.errorMessage {
            model = .init(symbol: "wifi.exclamationmark", title: L10n.Explore.errorTitle, message: error, actionTitle: L10n.Common.retry)
        } else {
            model = .init(
                symbol: "magnifyingglass",
                title: L10n.Explore.emptyTitle,
                message: L10n.Explore.emptyMessage,
                actionTitle: L10n.Explore.addPlace
            )
        }
        emptyStateView.configure(model)
        tableView.backgroundView = emptyStateView
    }

    private func syncCategorySelection(with category: VenueCategory?) {
        guard let index = categories.firstIndex(of: category) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard categoryCollectionView.indexPathsForSelectedItems?.first != indexPath else { return }
        categoryCollectionView.selectItem(at: indexPath, animated: true, scrollPosition: .centeredHorizontally)
    }

    private func handle(_ event: ExploreViewModel.Event) {
        switch event {
        case .moveMap(let region):
            mapController?.setShowsUserLocation(container?.locationManager.authorization == .authorized)
            mapController?.setRegion(region, animated: view.window != nil)
            searchAreaButton.isHidden = true
        case .fitMapToResults:
            mapController?.fitToResults()
        case .showLocationDenied:
            presentLocationDeniedAlert()
        }
    }

    private func handleEmptyStateAction() {
        guard let viewModel else { return }
        if viewModel.state.errorMessage != nil {
            viewModel.retry()
        } else {
            showAddPlace()
        }
    }

    private func presentLocationDeniedAlert() {
        let alert = UIAlertController(title: L10n.Explore.locationDeniedTitle, message: L10n.Explore.locationDeniedMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.openSettings, style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }

    // MARK: Actions

    @IBAction private func viewModeChanged(_ sender: UISegmentedControl) {
        let showMap = sender.selectedSegmentIndex == 1
        searchBar.resignFirstResponder()
        AppComponents.selectionHaptic()
        UIView.transition(with: view, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.tableView.isHidden = showMap
            self.mapView.isHidden = !showMap
            self.locateButton.isHidden = !showMap
            // In map mode the locate button sits bottom-right, so lift Add Place above it.
            self.addPlaceBottom?.constant = showMap ? -(AppSpacing.l + 50 + AppSpacing.m) : -AppSpacing.l
            self.view.layoutIfNeeded()
            if !showMap { self.searchAreaButton.isHidden = true }
        }
    }

    @IBAction private func locationTapped(_ sender: UIButton) {
        if viewModel?.state.locationState == .denied {
            presentLocationDeniedAlert()
        } else {
            viewModel?.useMyLocation()
        }
    }

    @IBAction private func locateTapped(_ sender: UIButton) {
        viewModel?.useMyLocation()
    }

    @IBAction private func searchAreaTapped(_ sender: UIButton) {
        guard let region = mapController?.visibleRegion else { return }
        AppComponents.selectionHaptic()
        UIView.animate(withDuration: 0.2) { self.searchAreaButton.alpha = 0 } completion: { _ in
            self.searchAreaButton.isHidden = true
            self.searchAreaButton.alpha = 1
        }
        viewModel?.searchArea(region)
    }

    @IBAction private func filterTapped(_ sender: UIButton) {
        searchBar.resignFirstResponder()
        performSegue(withIdentifier: Segue.presentFilter, sender: sender)
    }

    private func showDetail(for venue: VenueSummary) {
        searchBar.resignFirstResponder()
        pendingDetail = venue
        performSegue(withIdentifier: Segue.showVenueDetail, sender: self)
    }

    private func showAddPlace() {
        searchBar.resignFirstResponder()
        performSegue(withIdentifier: Segue.presentAddPlace, sender: self)
    }

    private func renderFooter(_ state: ExploreViewModel.State) {
        guard !state.isEmpty else {
            tableView.tableFooterView = nil
            return
        }
        footerView.configure(hasMore: state.hasMore, isLoadingMore: state.isLoadingMore)
        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        let size = footerView.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        footerView.frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        tableView.tableFooterView = footerView
    }

    // MARK: Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let container else { return }
        switch segue.identifier {
        case Segue.showVenueDetail:
            guard let detail = segue.destination as? VenueDetailViewController, let venue = pendingDetail else { return }
            detail.configure(viewModel: container.makeVenueDetailViewModel(venue: venue), container: container)
            pendingDetail = nil
        case Segue.presentAddPlace:
            guard let navigation = segue.destination as? UINavigationController,
                  let addPlace = navigation.topViewController as? AddPlaceViewController else { return }
            addPlace.configure(viewModel: container.makeAddPlaceViewModel(), container: container)
        case Segue.presentFilter:
            guard let navigation = segue.destination as? UINavigationController,
                  let filter = navigation.topViewController as? FilterViewController,
                  let viewModel else { return }
            filter.configure(viewModel: FilterViewModel(filter: viewModel.state.filter, limits: container.configuration.filter)) { [weak viewModel] newFilter in
                viewModel?.apply(newFilter)
            }
            if let sheet = navigation.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .large
                sheet.prefersGrabberVisible = true
            }
        default:
            break
        }
    }
}

// MARK: - UISearchBarDelegate

extension ExploreViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel?.updateQuery(searchText)
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        viewModel?.submitSearch()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        viewModel?.updateQuery("")
    }
}

// MARK: - UITableViewDelegate

extension ExploreViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = dataSource?.item(at: indexPath) else { return }
        showDetail(for: item.venue)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let viewModel, viewModel.state.hasMore else { return }
        let lastSection = tableView.numberOfSections - 1
        if indexPath.section == lastSection, indexPath.row >= tableView.numberOfRows(inSection: lastSection) - 3 {
            viewModel.loadMore()
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let model = dataSource?.section(at: section),
              let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderView.reuseIdentifier) as? SectionHeaderView
        else { return nil }
        header.configure(title: model.title, subtitle: model.subtitle)
        return header
    }
}

// MARK: - Category chips

extension ExploreViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        categories.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CategoryChipCell.reuseIdentifier, for: indexPath)
        let category = categories[indexPath.item]
        (cell as? CategoryChipCell)?.configure(
            title: category?.title ?? L10n.Category.all,
            symbol: category?.symbol ?? "sparkles"
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        AppComponents.selectionHaptic()
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        viewModel?.selectCategory(categories[indexPath.item])
    }
}
