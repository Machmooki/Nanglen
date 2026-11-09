import MapKit
import PhotosUI
import UIKit

/// Add / resubmit a place (Storyboard scene `AddPlaceViewController` in `AddPlaceNavigationController`).
final class AddPlaceViewController: UIViewController {
    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var introLabel: UILabel!
    @IBOutlet private weak var searchMapsButton: UIButton!
    @IBOutlet private weak var mapView: MKMapView!
    @IBOutlet private weak var pinHintLabel: UILabel!
    @IBOutlet private weak var nameTextField: UITextField!
    @IBOutlet private weak var categoryTitleLabel: UILabel!
    @IBOutlet private weak var categoryControl: UISegmentedControl!
    @IBOutlet private weak var addressTextField: UITextField!
    @IBOutlet private weak var descriptionTextView: UITextView!
    @IBOutlet private weak var websiteTextField: UITextField!
    @IBOutlet private weak var phoneTextField: UITextField!
    @IBOutlet private weak var noteTextField: UITextField!
    @IBOutlet private weak var photosTitleLabel: UILabel!
    @IBOutlet private weak var photoStrip: PhotoStripView!
    @IBOutlet private weak var issuesLabel: UILabel!
    @IBOutlet private weak var submitButton: UIButton!

    private var viewModel: AddPlaceViewModel?
    private weak var container: AppContainer?
    private let pinView = UIImageView(image: UIImage(systemName: "mappin"))
    private var isApplyingRegion = false

    func configure(viewModel: AddPlaceViewModel, container: AppContainer) {
        self.viewModel = viewModel
        self.container = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let viewModel else {
            assertionFailure("AddPlaceViewController needs configure(viewModel:container:)")
            return
        }
        setUpAppearance(viewModel)
        viewModel.onChange = { [weak self] state in self?.render(state) }
        viewModel.onOutcome = { [weak self] outcome in self?.handle(outcome) }
        render(viewModel.state)
        viewModel.start()
        isModalInPresentation = true
    }

    private func setUpAppearance(_ viewModel: AddPlaceViewModel) {
        view.backgroundColor = AppColors.background
        title = L10n.Submission.title
        introLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        introLabel.text = L10n.Submission.intro
        AppStyles.secondaryButton(searchMapsButton, title: L10n.Submission.searchMaps, systemImage: "magnifyingglass")
        pinHintLabel.apply(AppTypography.caption, color: AppColors.textSecondary)
        pinHintLabel.text = L10n.Submission.pinHint
        mapView.delegate = self
        mapView.layer.cornerRadius = AppRadius.card
        mapView.layer.cornerCurve = .continuous
        mapView.pointOfInterestFilter = .includingAll
        pinView.tintColor = AppColors.bad
        pinView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .bold)
        pinView.translatesAutoresizingMaskIntoConstraints = false
        pinView.isAccessibilityElement = false
        mapView.addSubview(pinView)
        NSLayoutConstraint.activate([
            pinView.centerXAnchor.constraint(equalTo: mapView.centerXAnchor),
            pinView.bottomAnchor.constraint(equalTo: mapView.centerYAnchor),
        ])
        moveMap(to: viewModel.initialCenter)

        style(nameTextField, L10n.Submission.name, id: "addPlace.name")
        style(addressTextField, L10n.Submission.address, id: "addPlace.address")
        style(websiteTextField, L10n.Submission.website, id: "addPlace.website")
        websiteTextField.keyboardType = .URL
        websiteTextField.autocapitalizationType = .none
        style(phoneTextField, L10n.Submission.phone, id: "addPlace.phone")
        phoneTextField.keyboardType = .phonePad
        style(noteTextField, L10n.Submission.note, id: "addPlace.note")
        AppStyles.sectionTitle(categoryTitleLabel)
        categoryTitleLabel.text = L10n.Submission.category
        categoryControl.removeAllSegments()
        // Icons keep five segments readable at large text sizes; the selected title is shown in the label above.
        for (index, category) in VenueCategory.allCases.enumerated() {
            let image = UIImage(systemName: category.symbol)
            image?.accessibilityLabel = category.title
            categoryControl.insertSegment(with: image, at: index, animated: false)
        }
        AppStyles.segmentedControl(categoryControl)
        descriptionTextView.font = AppTypography.body
        descriptionTextView.adjustsFontForContentSizeCategory = true
        descriptionTextView.backgroundColor = AppColors.card
        descriptionTextView.layer.cornerRadius = AppRadius.control
        descriptionTextView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        descriptionTextView.delegate = self
        descriptionTextView.accessibilityLabel = L10n.Submission.description
        AppStyles.sectionTitle(photosTitleLabel)
        photosTitleLabel.text = L10n.Submission.photos
        photoStrip.maximumCount = viewModel.configuration.submissionMaxPhotos
        photoStrip.onAdd = { [weak self] in self?.pickPhoto() }
        photoStrip.onRemove = { [weak self] index in self?.viewModel?.removePhoto(at: index) }
        photoStrip.isHidden = viewModel.editing != nil
        photosTitleLabel.isHidden = viewModel.editing != nil
        issuesLabel.apply(AppTypography.footnote, color: AppColors.bad)
        submitButton.accessibilityIdentifier = "addPlace.submit"
        scrollView.keyboardDismissMode = .interactive

        let draft = viewModel.state.draft
        nameTextField.text = draft.name
        addressTextField.text = draft.address
        descriptionTextView.text = draft.description.isEmpty ? L10n.Submission.description : draft.description
        descriptionTextView.textColor = draft.description.isEmpty ? AppColors.textTertiary : AppColors.textPrimary
        websiteTextField.text = draft.websiteURL
        phoneTextField.text = draft.phoneNumber
        noteTextField.text = draft.note
    }

    private func style(_ field: UITextField, _ placeholder: String, id: String) {
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.accessibilityIdentifier = id
        field.font = AppTypography.body
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .none
        field.backgroundColor = AppColors.card
        field.layer.cornerRadius = AppRadius.control
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        field.addAction(UIAction { [weak self] _ in self?.fieldsChanged() }, for: .editingChanged)
    }

    private func render(_ state: AddPlaceViewModel.State) {
        guard let viewModel else { return }
        if nameTextField.text != state.draft.name, !nameTextField.isFirstResponder { nameTextField.text = state.draft.name }
        if addressTextField.text != state.draft.address, !addressTextField.isFirstResponder { addressTextField.text = state.draft.address }
        if websiteTextField.text != state.draft.websiteURL, !websiteTextField.isFirstResponder { websiteTextField.text = state.draft.websiteURL }
        if phoneTextField.text != state.draft.phoneNumber, !phoneTextField.isFirstResponder { phoneTextField.text = state.draft.phoneNumber }
        categoryControl.selectedSegmentIndex = state.draft.category.flatMap { VenueCategory.allCases.firstIndex(of: $0) } ?? UISegmentedControl.noSegment
        categoryTitleLabel.text = L10n.Submission.category + (state.draft.category.map { " · \($0.title)" } ?? "")
        photoStrip.setImages(state.photos)
        var messages: [String] = []
        if state.showValidation {
            messages += state.issues.map { issue in
                switch issue {
                case .nameRequired: L10n.Submission.nameRequired
                case .categoryRequired: L10n.Submission.categoryRequired
                case .locationRequired: L10n.Submission.locationRequired
                case .invalidWebsite: L10n.Submission.invalidWebsite
                case .textTooLong: L10n.Submission.textTooLong
                }
            }
        }
        if let error = state.errorMessage { messages.append(error) }
        issuesLabel.text = messages.joined(separator: "\n")
        issuesLabel.isHidden = messages.isEmpty
        let title = viewModel.editing == nil ? L10n.Submission.submit : L10n.Submission.resubmit
        AppStyles.primaryButton(submitButton, title: title, systemImage: "paperplane.fill")
        submitButton.isEnabled = !state.isSubmitting
        submitButton.configuration?.showsActivityIndicator = state.isSubmitting
    }

    private func moveMap(to point: GeoPoint) {
        isApplyingRegion = true
        mapView.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                                             latitudinalMeters: 400, longitudinalMeters: 400), animated: false)
        isApplyingRegion = false
    }

    private func fieldsChanged() {
        viewModel?.update { draft in
            draft.name = nameTextField.text ?? ""
            draft.address = addressTextField.text ?? ""
            draft.websiteURL = websiteTextField.text ?? ""
            draft.phoneNumber = phoneTextField.text ?? ""
            draft.note = noteTextField.text ?? ""
        }
    }

    private func handle(_ outcome: AddPlaceViewModel.Outcome) {
        switch outcome {
        case .submitted(let duplicates):
            AppComponents.successHaptic()
            var message = L10n.Submission.submittedMessage
            if !duplicates.isEmpty {
                message += "\n\n" + L10n.Submission.possibleDuplicates(duplicates.prefix(3).map(\.name).joined(separator: ", "))
            }
            let alert = UIAlertController(title: L10n.Submission.submitted, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.Common.ok, style: .default) { [weak self] _ in self?.dismiss(animated: true) })
            present(alert, animated: true)
        case .resubmitted:
            let presenter = presentingViewController
            dismiss(animated: true) { presenter?.showToast(L10n.Submission.submitted) }
        case .alreadyListed(let venueID):
            presentAlreadyListed(venueID)
        case .needsRegistration:
            let alert = UIAlertController(title: L10n.Account.registeredRequiredTitle, message: L10n.Account.registeredRequiredSubmit, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.Account.linkPhone, style: .default) { [weak self] _ in self?.presentPhoneLink() })
            present(alert, animated: true)
        }
    }

    private func presentAlreadyListed(_ venueID: UUID) {
        let alert = UIAlertController(title: L10n.Submission.alreadyListedTitle, message: L10n.Submission.alreadyListedMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Submission.openVenue, style: .default) { [weak self] _ in self?.openVenue(venueID) })
        present(alert, animated: true)
    }

    private func openVenue(_ venueID: UUID) {
        guard let viewModel, let container else { return }
        Task {
            guard let venue = await viewModel.venueSummary(id: venueID),
                  let detail = storyboard?.instantiateViewController(withIdentifier: "VenueDetailViewController") as? VenueDetailViewController
            else { return }
            detail.configure(viewModel: container.makeVenueDetailViewModel(venue: venue), container: container)
            navigationController?.pushViewController(detail, animated: true)
        }
    }

    private func presentPhoneLink() {
        guard let container,
              let navigation = storyboard?.instantiateViewController(withIdentifier: "PhoneLinkNavigationController") as? UINavigationController,
              let phone = navigation.topViewController as? PhoneLinkViewController else { return }
        phone.configure(viewModel: container.makePhoneLinkViewModel(), isDemo: container.isDemo)
        present(navigation, animated: true)
    }

    private func pickPhoto() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: Actions

    @IBAction private func searchMapsTapped(_ sender: UIButton) {
        guard let viewModel else { return }
        let candidates = PlaceCandidatesViewController(viewModel: viewModel) { [weak self] row in
            guard let self else { return }
            if let existing = row.existingVenueID {
                presentAlreadyListed(existing)
            } else {
                viewModel.select(row.candidate)
                moveMap(to: row.candidate.coordinate)
            }
        }
        let navigation = UINavigationController(rootViewController: candidates)
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    @IBAction private func categoryChanged(_ sender: UISegmentedControl) {
        let category = VenueCategory.allCases[safe: sender.selectedSegmentIndex]
        AppComponents.selectionHaptic()
        viewModel?.update { $0.category = category }
    }

    @IBAction private func submitTapped(_ sender: UIButton) {
        view.endEditing(true)
        fieldsChanged()
        viewModel?.submit()
    }

    @IBAction private func cancelTapped(_ sender: Any) {
        viewModel?.cancel()
        dismiss(animated: true)
    }
}

extension AddPlaceViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard !isApplyingRegion else { return }
        viewModel?.setPin(GeoPoint(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude))
    }
}

extension AddPlaceViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == AppColors.textTertiary {
            textView.text = ""
            textView.textColor = AppColors.textPrimary
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        viewModel?.update { $0.description = String(textView.text.prefix(1_000)) }
    }
}

extension AddPlaceViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            Task { @MainActor in self?.viewModel?.addPhoto(image) }
        }
    }
}

/// Transient sheet listing Apple Maps candidates. Each row says clearly whether it is already an
/// approved Nanglen venue; others are labelled "not yet on Nanglen".
final class PlaceCandidatesViewController: UITableViewController, UISearchBarDelegate {
    private let viewModel: AddPlaceViewModel
    private let onSelect: (AddPlaceViewModel.CandidateRow) -> Void
    private var rows: [AddPlaceViewModel.CandidateRow] = []
    private let searchBar = UISearchBar()
    private var task: Task<Void, Never>?

    init(viewModel: AddPlaceViewModel, onSelect: @escaping (AddPlaceViewModel.CandidateRow) -> Void) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.Submission.searchMaps
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        searchBar.placeholder = L10n.Submission.searchMapsPlaceholder
        searchBar.delegate = self
        searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.keyboardDismissMode = .onDrag
        searchBar.becomeFirstResponder()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            let results = await viewModel.searchCandidates(searchText)
            guard !Task.isCancelled else { return }
            rows = results
            tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let row = rows[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.candidate.name
        content.secondaryText = [row.existingVenueID == nil ? L10n.Submission.notOnNanglen : "✓ " + L10n.Submission.alreadyOnNanglen,
                                 row.candidate.address].compactMap { $0 }.joined(separator: "\n")
        content.secondaryTextProperties.color = row.existingVenueID == nil ? AppColors.textSecondary : AppColors.good
        content.image = UIImage(systemName: row.candidate.category.symbol)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = rows[indexPath.row]
        dismiss(animated: true) { [onSelect] in onSelect(row) }
    }
}
