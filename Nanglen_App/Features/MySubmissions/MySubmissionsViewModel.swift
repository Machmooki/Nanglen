import Foundation

final class MySubmissionsViewModel {
    struct State: Equatable {
        var submissions: [VenueSubmission] = []
        var isLoading = false
        var errorMessage: String?
    }

    var onChange: ((State) -> Void)?
    var onMessage: ((String) -> Void)?
    private(set) var state = State() { didSet { if state != oldValue { onChange?(state) } } }
    private let service: SubmissionService

    init(service: SubmissionService, notifier: DataChangeNotifier) {
        self.service = service
        notifier.subscribe(self) { [weak self] change in
            if change == .submissionsChanged { self?.load() }
        }
    }

    func load() {
        state.isLoading = state.submissions.isEmpty
        Task {
            defer { state.isLoading = false }
            do {
                state.submissions = try await service.mine()
                state.errorMessage = nil
            } catch {
                state.errorMessage = L10n.Errors.message(for: error)
            }
        }
    }

    func withdraw(_ submission: VenueSubmission) {
        Task {
            do {
                try await service.withdraw(id: submission.id)
            } catch {
                onMessage?(L10n.Errors.message(for: error))
            }
        }
    }
}
