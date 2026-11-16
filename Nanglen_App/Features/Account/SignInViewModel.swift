import Foundation

/// Free identity upgrade: verify an email with a 6-digit code.
/// - `link`: Guest → Registered on this device, keeping the same user id (favorites stay).
/// - `signIn`: the email already has an account (e.g. another phone) → explicit switch to it.
/// Codes are verified by the auth backend; the app never verifies codes itself.
final class SignInViewModel {
    enum Mode: Equatable { case link, signIn }

    enum Step: Equatable {
        case enterEmail
        case enterCode(email: String, mode: Mode)
        case done(Mode)
    }

    struct State: Equatable {
        var step: Step = .enterEmail
        var isBusy = false
        var message: String?
        var isError = false
    }

    enum Prompt: Equatable {
        /// The email already has a Nanglen account; ask before switching to it.
        case accountExists(email: String)
    }

    var onChange: ((State) -> Void)?
    var onPrompt: ((Prompt) -> Void)?
    private(set) var state = State() { didSet { if state != oldValue { onChange?(state) } } }
    private let session: SessionService

    init(session: SessionService) {
        self.session = session
    }

    func sendCode(rawEmail: String) {
        run { [self] in
            try await session.start()
            do {
                let email = try await session.requestEmailLink(rawEmail: rawEmail)
                codeSent(to: email, mode: .link)
            } catch BackendError.accountExists {
                if let email = EmailAddress.normalized(rawEmail) { onPrompt?(.accountExists(email: email)) }
            }
        }
    }

    /// User chose to sign in to the existing account instead of linking.
    func signInInstead(email: String) {
        run { [self] in
            try await session.requestEmailSignIn(email: email)
            codeSent(to: email, mode: .signIn)
        }
    }

    func resend() {
        guard case .enterCode(let email, let mode) = state.step else { return }
        mode == .link ? sendCode(rawEmail: email) : signInInstead(email: email)
    }

    func verify(code: String) {
        guard case .enterCode(let email, let mode) = state.step else { return }
        run { [self] in
            switch mode {
            case .link: try await session.confirmEmailLink(email: email, code: code)
            case .signIn: try await session.confirmEmailSignIn(email: email, code: code)
            }
            state.step = .done(mode)
        }
    }

    func changeEmail() {
        state = State()
    }

    private func codeSent(to email: String, mode: Mode) {
        state.step = .enterCode(email: email, mode: mode)
        state.message = L10n.Account.codeSent(EmailAddress.masked(email))
        state.isError = false
    }

    private func run(_ work: @escaping () async throws -> Void) {
        guard !state.isBusy else { return }
        state.isBusy = true
        state.message = nil
        Task {
            defer { state.isBusy = false }
            do {
                try await work()
            } catch {
                state.message = L10n.Errors.message(for: error)
                state.isError = true
            }
        }
    }
}
