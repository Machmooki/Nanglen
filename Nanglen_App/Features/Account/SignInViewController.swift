import UIKit

/// Email-code sign-in (Storyboard scene `SignInViewController` in `SignInNavigationController`).
final class SignInViewController: UIViewController {
    @IBOutlet private weak var introLabel: UILabel!
    @IBOutlet private weak var emailTextField: UITextField!
    @IBOutlet private weak var sendCodeButton: UIButton!
    @IBOutlet private weak var codeTextField: UITextField!
    @IBOutlet private weak var verifyButton: UIButton!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var demoHintLabel: UILabel!

    private var viewModel: SignInViewModel?
    private var isDemo = false
    private var onLinked: (() -> Void)?
    private var didFinish = false
    private let changeEmailButton = UIButton(type: .system)

    func configure(viewModel: SignInViewModel, isDemo: Bool, onLinked: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.isDemo = isDemo
        self.onLinked = onLinked
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        title = L10n.Account.verifyEmail
        introLabel.apply(AppTypography.subheadline, color: AppColors.textSecondary)
        introLabel.text = L10n.Account.verifyEmailBenefit
        styleField(emailTextField, placeholder: L10n.Account.emailPlaceholder)
        emailTextField.keyboardType = .emailAddress
        emailTextField.textContentType = .emailAddress
        emailTextField.autocapitalizationType = .none
        emailTextField.autocorrectionType = .no
        emailTextField.returnKeyType = .send
        emailTextField.accessibilityIdentifier = "signIn.email"
        emailTextField.addAction(UIAction { [weak self] _ in self?.sendCodeTapped(nil) }, for: .editingDidEndOnExit)
        styleField(codeTextField, placeholder: L10n.Account.codePlaceholder)
        codeTextField.keyboardType = .numberPad
        codeTextField.textContentType = .oneTimeCode
        codeTextField.accessibilityIdentifier = "signIn.code"
        codeTextField.addAction(UIAction { [weak self] _ in self?.autoSubmitIfComplete() }, for: .editingChanged)
        statusLabel.apply(AppTypography.footnote, color: AppColors.textSecondary)
        demoHintLabel.apply(AppTypography.footnote, color: AppColors.warning)
        var hint = L10n.Account.demoOTPHint(DemoSeed.demoOTP)
        #if DEBUG
        hint += "\n" + L10n.Profile.demoAdminHint(DemoSeed.adminEmail)
        #endif
        demoHintLabel.text = isDemo ? hint : L10n.Account.emailPrivacy
        demoHintLabel.textColor = isDemo ? AppColors.warning : AppColors.textTertiary
        sendCodeButton.accessibilityIdentifier = "signIn.send"
        verifyButton.accessibilityIdentifier = "signIn.verify"

        var change = UIButton.Configuration.plain()
        change.title = L10n.Account.useDifferentEmail
        changeEmailButton.configuration = change
        changeEmailButton.addAction(UIAction { [weak self] _ in self?.viewModel?.changeEmail() }, for: .primaryActionTriggered)
        if let stack = verifyButton.superview as? UIStackView, let index = stack.arrangedSubviews.firstIndex(of: verifyButton) {
            stack.insertArrangedSubview(changeEmailButton, at: index + 1)
        }

        viewModel?.onChange = { [weak self] state in self?.render(state) }
        viewModel?.onPrompt = { [weak self] prompt in self?.handle(prompt) }
        render(viewModel?.state ?? .init())
        emailTextField.becomeFirstResponder()
    }

    private func styleField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        field.font = AppTypography.body
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .none
        field.backgroundColor = AppColors.card
        field.layer.cornerRadius = AppRadius.control
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
    }

    private func render(_ state: SignInViewModel.State) {
        let codeStep: Bool
        switch state.step {
        case .enterEmail:
            codeStep = false
            codeTextField.text = nil
        case .enterCode:
            codeStep = true
        case .done(let mode):
            guard !didFinish else { return }
            didFinish = true
            AppComponents.successHaptic()
            let onLinked = onLinked
            let presenter = presentingViewController
            let message = mode == .link ? L10n.Account.linked : L10n.Account.signedIn
            dismiss(animated: true) {
                presenter?.showToast(message)
                onLinked?()
            }
            return
        }
        emailTextField.isEnabled = !codeStep && !state.isBusy
        emailTextField.alpha = codeStep ? 0.6 : 1
        codeTextField.isHidden = !codeStep
        verifyButton.isHidden = !codeStep
        changeEmailButton.isHidden = !codeStep
        if codeStep {
            AppStyles.secondaryButton(sendCodeButton, title: L10n.Account.resendCode, systemImage: "arrow.clockwise")
        } else {
            AppStyles.primaryButton(sendCodeButton, title: L10n.Account.sendCode, systemImage: "envelope.fill")
        }
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

    private func handle(_ prompt: SignInViewModel.Prompt) {
        switch prompt {
        case .accountExists(let email):
            let alert = UIAlertController(title: L10n.Account.accountExistsTitle, message: L10n.Account.accountExistsMessage(email), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.Common.cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: L10n.Account.signInInstead, style: .default) { [weak self] _ in
                self?.viewModel?.signInInstead(email: email)
            })
            present(alert, animated: true)
        }
    }

    /// One-time codes arrive as 6 digits; verify automatically when complete (AutoFill friendly).
    private func autoSubmitIfComplete() {
        let digits = (codeTextField.text ?? "").filter(\.isNumber)
        if digits.count == 6 { viewModel?.verify(code: digits) }
    }

    @IBAction private func sendCodeTapped(_ sender: UIButton?) {
        if case .enterCode = viewModel?.state.step {
            viewModel?.resend()
        } else {
            viewModel?.sendCode(rawEmail: emailTextField.text ?? "")
        }
    }

    @IBAction private func verifyTapped(_ sender: UIButton) {
        viewModel?.verify(code: codeTextField.text ?? "")
    }

    @IBAction private func closeTapped(_ sender: Any) {
        dismiss(animated: true)
    }
}
