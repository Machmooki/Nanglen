import UIKit

/// The submitter's venue submissions with status and Admin feedback (Storyboard `MySubmissionsViewController`).
final class MySubmissionsViewController: UITableViewController {
    private var viewModel: MySubmissionsViewModel?
    private weak var container: AppContainer?
    private var submissions: [VenueSubmission] = []
    private let emptyStateView = EmptyStateView()

    func configure(viewModel: MySubmissionsViewModel, container: AppContainer) {
        self.viewModel = viewModel
        self.container = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.Submission.mine
        tableView.backgroundColor = AppColors.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SubmissionCell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.presentAddPlace(editing: nil) })
        navigationItem.rightBarButtonItem?.accessibilityLabel = L10n.Profile.addPlace
        viewModel?.onChange = { [weak self] state in self?.render(state) }
        viewModel?.onMessage = { [weak self] message in self?.showToast(message) }
        refreshControl = UIRefreshControl()
        refreshControl?.addAction(UIAction { [weak self] _ in
            self?.viewModel?.load()
            self?.refreshControl?.endRefreshing()
        }, for: .valueChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel?.load()
    }

    private func render(_ state: MySubmissionsViewModel.State) {
        submissions = state.submissions
        tableView.reloadData()
        if submissions.isEmpty {
            if state.isLoading {
                emptyStateView.configure(.init(symbol: nil, title: L10n.Common.loading, message: nil, actionTitle: nil, isLoading: true))
            } else {
                emptyStateView.configure(.init(symbol: "tray", title: state.errorMessage ?? L10n.Submission.mineEmpty,
                                               message: state.errorMessage == nil ? L10n.Submission.intro : nil, actionTitle: L10n.Profile.addPlace))
                emptyStateView.onAction = { [weak self] in self?.presentAddPlace(editing: nil) }
            }
            tableView.backgroundView = emptyStateView
        } else {
            tableView.backgroundView = nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { submissions.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SubmissionCell", for: indexPath)
        let submission = submissions[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = submission.name
        var lines = ["\(submission.status.title) · \(submission.category.title)"]
        if let reason = submission.decisionReason, [.needsChanges, .rejected, .duplicate].contains(submission.status) {
            lines.append("\(L10n.Submission.adminFeedback): \(reason)")
        }
        if let date = submission.submittedAt { lines.append(Formatters.relative(date)) }
        content.secondaryText = lines.joined(separator: "\n")
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = AppColors.textSecondary
        content.image = UIImage(systemName: submission.status.symbol)
        content.imageProperties.tintColor = submission.status.tone.foreground
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let submission = submissions[indexPath.row]
        let sheet = UIAlertController(title: submission.name, message: [submission.status.title, submission.decisionReason].compactMap { $0 }.joined(separator: "\n"), preferredStyle: .actionSheet)
        if let venueID = submission.approvedVenueID ?? submission.duplicateOfVenueID {
            sheet.addAction(UIAlertAction(title: L10n.Submission.openVenue, style: .default) { [weak self] _ in self?.openVenue(venueID) })
        }
        if submission.status.canResubmit {
            sheet.addAction(UIAlertAction(title: L10n.Submission.editAndResubmit, style: .default) { [weak self] _ in self?.presentAddPlace(editing: submission) })
        }
        if submission.status.canWithdraw {
            sheet.addAction(UIAlertAction(title: L10n.Submission.withdraw, style: .destructive) { [weak self] _ in self?.viewModel?.withdraw(submission) })
        }
        sheet.addAction(UIAlertAction(title: L10n.Common.close, style: .cancel))
        sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(sheet, animated: true)
    }

    private func presentAddPlace(editing: VenueSubmission?) {
        guard let container,
              let navigation = storyboard?.instantiateViewController(withIdentifier: "AddPlaceNavigationController") as? UINavigationController,
              let addPlace = navigation.topViewController as? AddPlaceViewController else { return }
        addPlace.configure(viewModel: container.makeAddPlaceViewModel(editing: editing), container: container)
        present(navigation, animated: true)
    }

    private func openVenue(_ id: UUID) {
        guard let container else { return }
        Task {
            guard let detail = try? await container.venues.detail(id: id),
                  let controller = storyboard?.instantiateViewController(withIdentifier: "VenueDetailViewController") as? VenueDetailViewController else { return }
            controller.configure(viewModel: container.makeVenueDetailViewModel(venue: detail.summary), container: container)
            navigationController?.pushViewController(controller, animated: true)
        }
    }
}
