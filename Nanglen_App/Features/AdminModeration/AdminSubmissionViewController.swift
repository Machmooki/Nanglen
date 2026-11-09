import MapKit
import UIKit

/// One pending submission with map, photos, duplicate candidates and decision buttons
/// (Storyboard `AdminSubmissionViewController`). Decisions call protected, audited RPCs.
final class AdminSubmissionViewController: UIViewController {
    @IBOutlet private weak var mapView: MKMapView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var detailsLabel: UILabel!
    @IBOutlet private weak var submitterLabel: UILabel!
    @IBOutlet private weak var photosStackView: UIStackView!
    @IBOutlet private weak var duplicatesTitleLabel: UILabel!
    @IBOutlet private weak var duplicatesStackView: UIStackView!
    @IBOutlet private weak var historyLabel: UILabel!
    @IBOutlet private weak var errorLabel: UILabel!
    @IBOutlet private weak var approveButton: UIButton!
    @IBOutlet private weak var changesButton: UIButton!
    @IBOutlet private weak var rejectButton: UIButton!

    private var viewModel: AdminSubmissionViewModel?
    private var didFinish = false

    func configure(viewModel: AdminSubmissionViewModel) {
        self.viewModel = viewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        navigationItem.largeTitleDisplayMode = .never
        mapView.layer.cornerRadius = AppRadius.card
        mapView.pointOfInterestFilter = .includingAll
        nameLabel.apply(AppTypography.title)
        detailsLabel.apply(AppTypography.subheadline)
        detailsLabel.numberOfLines = 0
        submitterLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        AppStyles.sectionTitle(duplicatesTitleLabel)
        duplicatesTitleLabel.text = L10n.Admin.duplicates
        historyLabel.apply(AppTypography.caption, color: AppColors.textTertiary)
        historyLabel.numberOfLines = 0
        errorLabel.apply(AppTypography.footnote, color: AppColors.bad)
        AppStyles.primaryButton(approveButton, title: L10n.Admin.approve, systemImage: "checkmark.seal.fill")
        AppStyles.secondaryButton(changesButton, title: L10n.Admin.requestChanges, systemImage: "pencil")
        AppStyles.secondaryButton(rejectButton, title: L10n.Admin.reject, systemImage: "xmark.octagon")
        rejectButton.configuration?.baseForegroundColor = AppColors.bad
        approveButton.accessibilityIdentifier = "admin.approve"
        viewModel?.onChange = { [weak self] state in self?.render(state) }
        viewModel?.onPrompt = { [weak self] prompt in self?.handle(prompt) }
        render(viewModel?.state ?? .init())
        Task { await viewModel?.load() }
    }

    private func render(_ state: AdminSubmissionViewModel.State) {
        if state.finished {
            guard !didFinish else { return }
            didFinish = true
            navigationController?.popViewController(animated: true)
            showToast(L10n.Admin.done)
            return
        }
        errorLabel.text = state.errorMessage
        errorLabel.isHidden = state.errorMessage == nil
        [approveButton, changesButton, rejectButton].forEach { $0?.isEnabled = !state.isWorking && state.detail?.submission.status == .pendingReview }
        approveButton.configuration?.showsActivityIndicator = state.isWorking
        guard let detail = state.detail else { return }
        let submission = detail.submission
        title = submission.status.title
        nameLabel.text = submission.name
        var lines = ["\(submission.category.title) · rev \(submission.revision)"]
        if let address = submission.address { lines.append("📍 " + address) }
        lines.append(String(format: "%.6f, %.6f", submission.coordinate.latitude, submission.coordinate.longitude))
        if let provider = detail.provider, let ext = detail.externalPlaceID { lines.append("\(provider): \(ext)") }
        if let description = submission.description { lines.append("“\(description)”") }
        if let website = submission.websiteURL { lines.append("🌐 " + website) }
        if let phone = submission.phoneNumber { lines.append("☎︎ " + phone) }
        if let note = submission.note { lines.append("✉︎ " + note) }
        detailsLabel.text = lines.joined(separator: "\n")
        submitterLabel.text = L10n.Admin.submitter + ": " + L10n.Admin.submitterStats(detail.submitterName, detail.submitterApproved, detail.submitterTotal)

        let coordinate = CLLocationCoordinate2D(latitude: submission.coordinate.latitude, longitude: submission.coordinate.longitude)
        mapView.removeAnnotations(mapView.annotations)
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        pin.title = submission.name
        mapView.addAnnotation(pin)
        mapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400), animated: false)

        AppComponents.replaceArrangedSubviews(of: photosStackView, with: state.mediaURLs.prefix(4).map { url in
            let image = RemoteImageView()
            image.load(url)
            image.heightAnchor.constraint(equalToConstant: 90).isActive = true
            return image
        })
        photosStackView.isHidden = state.mediaURLs.isEmpty

        var rows: [UIView] = detail.duplicates.map { candidate in
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.gray()
            config.title = candidate.name
            config.subtitle = [Formatters.distance(candidate.distanceMeters),
                               "sim \(Int((candidate.nameSimilarity * 100).rounded()))%",
                               candidate.providerMatch ? "Apple Maps ✓" : nil,
                               L10n.Admin.markDuplicate].compactMap { $0 }.joined(separator: " · ")
            config.titleAlignment = .leading
            config.cornerStyle = .medium
            button.configuration = config
            button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { [weak self] _ in self?.confirmDuplicate(candidate) }, for: .primaryActionTriggered)
            return button
        }
        if rows.isEmpty {
            let label = UILabel()
            label.apply(AppTypography.footnote, color: AppColors.textSecondary)
            label.text = L10n.Admin.noDuplicates
            rows = [label]
        }
        AppComponents.replaceArrangedSubviews(of: duplicatesStackView, with: rows)
        historyLabel.text = detail.history.isEmpty ? nil : L10n.Admin.history + "\n" + detail.history.map {
            "• \($0.action) · \(Formatters.relative($0.createdAt))" + ($0.reason.map { " — \($0)" } ?? "")
        }.joined(separator: "\n")
        historyLabel.isHidden = detail.history.isEmpty
    }

    private func confirmDuplicate(_ candidate: DuplicateCandidate) {
        askReason(title: L10n.Admin.markDuplicate + ": " + candidate.name) { [weak self] reason in
            self?.viewModel?.decide(.markDuplicate(venueID: candidate.venueID, reason: reason))
        }
    }

    private func handle(_ prompt: AdminSubmissionViewModel.Prompt) {
        let alert = UIAlertController(title: L10n.Admin.likelyDuplicate, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Admin.approveAnyway, style: .destructive) { [weak self] _ in
            self?.viewModel?.decide(.approve(note: nil, force: true))
        })
        present(alert, animated: true)
    }

    @IBAction private func approveTapped(_ sender: UIButton) {
        askReason(title: L10n.Admin.approve, required: false) { [weak self] note in
            self?.viewModel?.decide(.approve(note: note.isEmpty ? nil : note, force: false))
        }
    }

    @IBAction private func changesTapped(_ sender: UIButton) {
        askReason { [weak self] reason in self?.viewModel?.decide(.requestChanges(reason: reason)) }
    }

    @IBAction private func rejectTapped(_ sender: UIButton) {
        askReason { [weak self] reason in self?.viewModel?.decide(.reject(reason: reason)) }
    }
}
