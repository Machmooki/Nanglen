import UIKit

/// Admin moderation queue (Storyboard `AdminQueueViewController`). Shown only to backend-authorized Admins.
final class AdminQueueViewController: UITableViewController {
    private enum Segue { static let showAdminSubmission = "showAdminSubmission" }

    private var viewModel: AdminQueueViewModel?
    private weak var container: AppContainer?
    private var state = AdminQueueViewModel.State()
    private let segmented = UISegmentedControl(items: [L10n.Admin.submissions, L10n.Admin.flagged])
    private let emptyStateView = EmptyStateView()
    private var pendingSubmissionID: UUID?

    func configure(viewModel: AdminQueueViewModel, container: AppContainer) {
        self.viewModel = viewModel
        self.container = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.Admin.title
        tableView.backgroundColor = AppColors.background
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AdminCell")
        segmented.selectedSegmentIndex = 0
        AppStyles.segmentedControl(segmented)
        segmented.addAction(UIAction { [weak self] _ in
            guard let self, let tab = AdminQueueViewModel.Tab(rawValue: segmented.selectedSegmentIndex) else { return }
            viewModel?.select(tab)
        }, for: .valueChanged)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 52))
        segmented.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(segmented)
        NSLayoutConstraint.activate([
            segmented.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            segmented.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            segmented.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
        ])
        tableView.tableHeaderView = header
        viewModel?.onChange = { [weak self] state in
            self?.state = state
            self?.render()
        }
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

    private var rowCount: Int {
        switch state.tab {
        case .submissions: state.submissions.count
        case .flagged: state.flagged.count
        }
    }

    private func render() {
        tableView.reloadData()
        if rowCount == 0 {
            emptyStateView.configure(state.isLoading
                ? .init(symbol: nil, title: L10n.Common.loading, message: nil, actionTitle: nil, isLoading: true)
                : .init(symbol: "checkmark.shield", title: state.errorMessage ?? L10n.Admin.empty, message: nil, actionTitle: nil))
            tableView.backgroundView = emptyStateView
        } else {
            tableView.backgroundView = nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rowCount }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AdminCell", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = AppColors.textSecondary
        switch state.tab {
        case .submissions:
            let row = state.submissions[indexPath.row]
            content.text = row.name
            var parts = [row.category.title, row.submitterName, L10n.Admin.photosCount(row.mediaCount)]
            if row.duplicateCandidateCount > 0 { parts.append(L10n.Admin.dupCount(row.duplicateCandidateCount)) }
            if let date = row.submittedAt { parts.append(Formatters.relative(date)) }
            content.secondaryText = parts.joined(separator: " · ")
            content.image = UIImage(systemName: row.category.symbol)
            cell.accessoryType = .disclosureIndicator
        case .flagged:
            let row = state.flagged[indexPath.row]
            content.text = "\(row.venueName) · \(StarText.stars(row.rating))"
            content.secondaryText = [L10n.Admin.flags(row.openFlags, row.reasons.joined(separator: ", ")), row.authorName, row.body].compactMap { $0 }.joined(separator: "\n")
            content.image = UIImage(systemName: "flag.fill")
            content.imageProperties.tintColor = AppColors.bad
            cell.accessoryType = .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch state.tab {
        case .submissions:
            pendingSubmissionID = state.submissions[indexPath.row].id
            performSegue(withIdentifier: Segue.showAdminSubmission, sender: self)
        case .flagged:
            let review = state.flagged[indexPath.row]
            let sheet = UIAlertController(title: review.venueName, message: review.body, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: L10n.Admin.dismiss, style: .default) { [weak self] _ in
                self?.askReason { reason in self?.viewModel?.moderate(review, status: .published, reason: reason) }
            })
            sheet.addAction(UIAlertAction(title: L10n.Admin.hide, style: .destructive) { [weak self] _ in
                self?.askReason { reason in self?.viewModel?.moderate(review, status: .hidden, reason: reason) }
            })
            sheet.addAction(UIAlertAction(title: L10n.Admin.removeReview, style: .destructive) { [weak self] _ in
                self?.askReason { reason in self?.viewModel?.moderate(review, status: .removed, reason: reason) }
            })
            sheet.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
            sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            present(sheet, animated: true)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier == Segue.showAdminSubmission, let container, let id = pendingSubmissionID,
              let detail = segue.destination as? AdminSubmissionViewController else { return }
        detail.configure(viewModel: container.makeAdminSubmissionViewModel(id: id))
    }
}

extension UIViewController {
    /// Asks an Admin for a required reason (shown to the affected user).
    func askReason(title: String = L10n.Admin.reasonTitle, required: Bool = true, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = required ? L10n.Admin.reasonTitle : L10n.Admin.notePlaceholder }
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Common.ok, style: .default) { [weak alert] _ in
            let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !required || !text.isEmpty else { return }
            completion(text)
        })
        present(alert, animated: true)
    }
}
