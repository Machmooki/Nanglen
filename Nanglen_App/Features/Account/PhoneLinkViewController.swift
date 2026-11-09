import UIKit

/// Phone OTP linking (Storyboard scene `PhoneLinkViewController` in `PhoneLinkNavigationController`).
final class PhoneLinkViewController: UIViewController {
    @IBOutlet private weak var introLabel: UILabel!
    @IBOutlet private weak var phoneTextField: UITextField!
    @IBOutlet private weak var sendCodeButton: UIButton!
    @IBOutlet private weak var codeTextField: UITextField!
    @IBOutlet private weak var verifyButton: UIButton!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var demoHintLabel: UILabel!

    private var viewModel: PhoneLinkViewModel?
    private var isDemo = false
    private var onLinked: (() -> Void)?
    private var didFinish = false

    func configure(viewModel: PhoneLinkViewModel, isDemo: Bool, onLinked: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.isDemo = isDemo
        self.onLinked = onLinked
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        title = L10n.Account.linkPhone
        introLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        introLabel.text = L10n.Account.linkPhoneBenefit
        styleField(phoneTextField, placeholder: L10n.Account.phonePlaceholder)
        phoneTextField.keyboardType = .phonePad
        phoneTextField.textContentType = .telephoneNumber
        phoneTextField.accessibilityIdentifier = "phone.number"
        styleField(codeTextField, placeholder: L10n.Account.codePlaceholder)
        codeTextField.keyboardType = .numberPad
        codeTextField.textContentType = .oneTimeCode
        codeTextField.accessibilityIdentifier = "phone.code"
        statusLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        demoHintLabel.apply(AppTypography.footnote, color: AppColors.warning)
        demoHintLabel.text = isDemo ? L10n.Account.demoOTPHint(DemoSeed.demoOTP) + "\n" + L10n.Profile.demoAdminHint(DemoSeed.adminPhone) : nil
        demoHintLabel.isHidden = !isDemo
        sendCodeButton.accessibilityIdentifier = "phone.send"
        verifyButton.accessibilityIdentifier = "phone.verify"
        viewModel?.onChange = { [weak self] state in self?.render(state) }
        render(viewModel?.state ?? .init())
    }

    private func styleField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.font = AppTypography.body
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .none
        field.backgroundColor = AppColors.card
        field.layer.cornerRadius = AppRadius.control
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
    }

    private func render(_ state: PhoneLinkViewModel.State) {
        let codeStep: Bool
        switch state.step {
        case .enterPhone: codeStep = false
        case .enterCode: codeStep = true
        case .linked:
            guard !didFinish else { return }
            didFinish = true
            AppComponents.successHaptic()
            let onLinked = onLinked
            let presenter = presentingViewController
            dismiss(animated: true) {
                presenter?.showToast(L10n.Account.linked)
                onLinked?()
            }
            return
        }
        phoneTextField.isEnabled = !codeStep && !state.isBusy
        codeTextField.isHidden = !codeStep
        verifyButton.isHidden = !codeStep
        AppStyles.primaryButton(sendCodeButton, title: L10n.Account.sendCode, systemImage: "message.fill")
        if codeStep { AppStyles.secondaryButton(sendCodeButton, title: L10n.Account.sendCode, systemImage: "arrow.clockwise") }
        AppStyles.primaryButton(verifyButton, title: L10n.Account.verifyCode, systemImage: "checkmark.shield.fill")
        sendCodeButton.isEnabled = !state.isBusy
        verifyButton.isEnabled = !state.isBusy
        sendCodeButton.configuration?.showsActivityIndicator = state.isBusy && !codeStep
        verifyButton.configuration?.showsActivityIndicator = state.isBusy && codeStep
        statusLabel.text = state.message
        statusLabel.textColor = state.isError ? AppColors.bad : AppColors.textSecondary
        statusLabel.isHidden = state.message == nil
        if codeStep, !codeTextField.isFirstResponder { codeTextField.becomeFirstResponder() }
    }

    @IBAction private func sendCodeTapped(_ sender: UIButton) {
        viewModel?.sendCode(rawPhone: phoneTextField.text ?? "")
    }

    @IBAction private func verifyTapped(_ sender: UIButton) {
        viewModel?.verify(code: codeTextField.text ?? "")
    }

    @IBAction private func closeTapped(_ sender: Any) {
        dismiss(animated: true)
    }
}
