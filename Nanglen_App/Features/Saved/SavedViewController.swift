import UIKit

final class SavedViewController: UIViewController, AppContainerConfigurable {
    private enum Segue {
        static let showVenueDetail = "showVenueDetail"
    }

    @IBOutlet private weak var tableView: UITableView!

    private var container: AppContainer?
    private var viewModel: SavedViewModel?
    private var dataSource: UITableViewDiffableDataSource<Int, UUID>?
    private var itemsByID: [UUID: VenueCardItem] = [:]
    private let emptyStateView = EmptyStateView()
    private var pendingDetail: VenueSummary?

    func configure(with container: AppContainer) {
        self.container = container
        viewModel = container.makeSavedViewModel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let viewModel else {
            assertionFailure("SavedViewController needs configure(with:)")
            return
        }
        view.backgroundColor = AppColors.background
        title = L10n.Saved.title
        navigationItem.backButtonDisplayMode = .minimal
        setUpTable()
        viewModel.onChange = { [weak self] state in self?.render(state) }
        viewModel.onMessage = { [weak self] message in self?.showToast(message) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let selected = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selected, animated: animated)
        }
        viewModel?.load()
    }

    private func setUpTable() {
        tableView.register(PlaceCardCell.nib, forCellReuseIdentifier: PlaceCardCell.reuseIdentifier)
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.contentInset = UIEdgeInsets(top: AppSpacing.s, left: 0, bottom: AppSpacing.l, right: 0)
        dataSource = UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, id in
            let cell = tableView.dequeueReusableCell(withIdentifier: PlaceCardCell.reuseIdentifier, for: indexPath)
            if let card = cell as? PlaceCardCell, let item = self?.itemsByID[id] {
                card.configure(with: item)
            }
            return cell
        }
        dataSource?.defaultRowAnimation = .fade
        emptyStateView.onAction = { [weak self] in self?.tabBarController?.selectedIndex = 0 }
    }

    private func render(_ state: SavedViewModel.State) {
        let previous = itemsByID
        itemsByID = Dictionary(state.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        var seen = Set<UUID>()
        snapshot.appendItems(state.items.map(\.id).filter { seen.insert($0).inserted })
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { previous[$0] != nil && previous[$0] != itemsByID[$0] })
        dataSource?.apply(snapshot, animatingDifferences: view.window != nil)

        if state.items.isEmpty {
            if state.isLoading {
                emptyStateView.configure(.init(symbol: nil, title: L10n.Explore.searching, message: nil, actionTitle: nil, isLoading: true))
            } else if let error = state.errorMessage {
                emptyStateView.configure(.init(symbol: "exclamationmark.triangle", title: error, message: nil, actionTitle: nil))
            } else {
                emptyStateView.configure(.init(symbol: "heart", title: L10n.Saved.emptyTitle, message: L10n.Saved.emptyMessage, actionTitle: L10n.Explore.title))
            }
            tableView.backgroundView = emptyStateView
        } else {
            tableView.backgroundView = nil
        }
        renderHeader(state)
    }

    private func renderHeader(_ state: SavedViewModel.State) {
        var notes: [String] = []
        if state.source != .live { notes.append(L10n.Saved.offline) }
        if state.isGuest && !state.items.isEmpty { notes.append(L10n.Saved.guestNote) }
        guard !notes.isEmpty else {
            tableView.tableHeaderView = nil
            return
        }
        let label = UILabel()
        label.apply(AppTypography.footnote, color: state.source != .live ? AppColors.warning : AppColors.textSecondary)
        label.numberOfLines = 0
        label.text = notes.joined(separator: "\n")
        let width = tableView.bounds.width > 0 ? tableView.bounds.width : view.bounds.width
        let container = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: AppSpacing.s),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -AppSpacing.s),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: AppSpacing.screenMargin),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -AppSpacing.screenMargin),
        ])
        let height = container.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        container.frame.size.height = height
        tableView.tableHeaderView = container
    }

    private func item(at indexPath: IndexPath) -> VenueCardItem? {
        dataSource?.itemIdentifier(for: indexPath).flatMap { itemsByID[$0] }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier == Segue.showVenueDetail,
              let detail = segue.destination as? VenueDetailViewController,
              let container, let venue = pendingDetail else { return }
        detail.configure(viewModel: container.makeVenueDetailViewModel(venue: venue), container: container)
        pendingDetail = nil
    }
}

extension SavedViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let item = item(at: indexPath) else { return }
        pendingDetail = item.venue
        performSegue(withIdentifier: Segue.showVenueDetail, sender: self)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = item(at: indexPath) else { return nil }
        let remove = UIContextualAction(style: .destructive, title: L10n.Common.remove) { [weak self] _, _, done in
            self?.viewModel?.remove(item)
            AppComponents.selectionHaptic()
            done(true)
        }
        remove.image = UIImage(systemName: "heart.slash.fill")
        let directions = UIContextualAction(style: .normal, title: L10n.Common.directions) { [weak self] _, _, done in
            self?.viewModel?.openDirections(to: item)
            done(true)
        }
        directions.image = UIImage(systemName: "arrow.triangle.turn.up.right.diamond.fill")
        directions.backgroundColor = AppColors.primary
        return UISwipeActionsConfiguration(actions: [remove, directions])
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = item(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: L10n.Common.directions, image: UIImage(systemName: "arrow.triangle.turn.up.right.diamond")) { _ in
                    self?.viewModel?.openDirections(to: item)
                },
                UIAction(title: L10n.Detail.unsave, image: UIImage(systemName: "heart.slash"), attributes: .destructive) { _ in
                    self?.viewModel?.remove(item)
                },
            ])
        })
    }
}
