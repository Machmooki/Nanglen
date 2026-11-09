import Foundation

/// Guest → Registered: link a verified phone number to the CURRENT user (same user id, data kept).
/// The OTP is verified by the auth backend; the app never verifies codes itself.
final class PhoneLinkViewModel {
    enum Step: Equatable {
        case enterPhone
        case enterCode(phoneE164: String)
        case linked
    }

    struct State: Equatable {
        var step: Step = .enterPhone
        var isBusy = false
        var message: String?
        var isError = false
    }

    var onChange: ((State) -> Void)?
    private(set) var state = State() { didSet { if state != oldValue { onChange?(state) } } }
    private let session: SessionService

    init(session: SessionService) {
        self.session = session
    }

    func sendCode(rawPhone: String) {
        guard !state.isBusy else { return }
        state.isBusy = true
        state.message = nil
        Task {
            defer { state.isBusy = false }
            do {
                try await session.start()
                let e164 = try await session.requestPhoneLink(rawPhone: rawPhone)
                state.step = .enterCode(phoneE164: e164)
                state.message = L10n.Account.codeSent(PhoneNumberFormatter.masked(e164))
                state.isError = false
            } catch {
                state.message = L10n.Errors.message(for: error)
                state.isError = true
            }
        }
    }

    func verify(code: String) {
        guard case .enterCode(let phone) = state.step, !state.isBusy else { return }
        state.isBusy = true
        state.message = nil
        Task {
            defer { state.isBusy = false }
            do {
                try await session.confirmPhoneLink(phoneE164: phone, code: code)
                state.step = .linked
                state.message = L10n.Account.linked
                state.isError = false
            } catch {
                state.message = L10n.Errors.message(for: error)
                state.isError = true
            }
        }
    }

    func editPhone() {
        state.step = .enterPhone
        state.message = nil
    }
}
