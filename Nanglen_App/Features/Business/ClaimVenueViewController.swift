import UIKit

/// Venue claim form (Storyboard `ClaimVenueViewController` in `ClaimNavigationController`).
final class ClaimVenueViewController: UIViewController {
    @IBOutlet private weak var introLabel: UILabel!
    @IBOutlet private weak var businessNameTextField: UITextField!
    @IBOutlet private weak var roleTitleLabel: UILabel!
    @IBOutlet private weak var roleControl: UISegmentedControl!
    @IBOutlet private weak var contactTextField: UITextField!
    @IBOutlet private weak var evidenceTextField: UITextField!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var submitButton: UIButton!

    private var viewModel: ClaimVenueViewModel?
    private var didFinish = false

    func configure(viewModel: ClaimVenueViewModel) {
        self.viewModel = viewModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        title = L10n.Claim.title
        introLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        introLabel.text = [viewModel?.venue.name, L10n.Claim.intro].compactMap { $0 }.joined(separator: "\n\n")
        style(businessNameTextField, L10n.Claim.businessName)
        style(contactTextField, L10n.Claim.contact)
        style(evidenceTextField, L10n.Claim.evidence)
        AppStyles.sectionTitle(roleTitleLabel)
        roleTitleLabel.text = L10n.Claim.role
        roleControl.removeAllSegments()
        for (index, role) in ClaimantRole.allCases.enumerated() { roleControl.insertSegment(withTitle: role.title, at: index, animated: false) }
        roleControl.selectedSegmentIndex = 0
        AppStyles.segmentedControl(roleControl)
        statusLabel.apply(AppTypography.footnote, color: AppColors.bad)
        viewModel?.onChange = { [weak self] state in self?.render(state) }
        render(viewModel?.state)
    }

    private func style(_ field: UITextField, _ placeholder: String) {
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
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

    private func fieldsChanged() {
        viewModel?.update { draft in
            draft.businessName = businessNameTextField.text ?? ""
            draft.contactNote = contactTextField.text ?? ""
            draft.evidenceNote = evidenceTextField.text ?? ""
        }
    }

    private func render(_ state: ClaimVenueViewModel.State?) {
        guard let state else { return }
        if state.submitted {
            guard !didFinish else { return }
            didFinish = true
            let presenter = presentingViewController
            dismiss(animated: true) { presenter?.showToast(L10n.Claim.submitted) }
            return
        }
        statusLabel.text = state.errorMessage
        statusLabel.isHidden = state.errorMessage == nil
        AppStyles.primaryButton(submitButton, title: L10n.Claim.submit, systemImage: "paperplane.fill")
        submitButton.isEnabled = !state.isSubmitting
        submitButton.configuration?.showsActivityIndicator = state.isSubmitting
    }

    @IBAction private func roleChanged(_ sender: UISegmentedControl) {
        let role = ClaimantRole.allCases[safe: sender.selectedSegmentIndex] ?? .owner
        viewModel?.update { $0.role = role }
    }

    @IBAction private func submitTapped(_ sender: UIButton) {
        view.endEditing(true)
        fieldsChanged()
        viewModel?.submit()
    }

    @IBAction private func cancelTapped(_ sender: Any) {
        dismiss(animated: true)
    }
}
