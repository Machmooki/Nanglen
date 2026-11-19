import Foundation

/// Admin queue. Visible only for server-authorized Admins; every action is re-authorized server-side.
final class AdminQueueViewModel {
    enum Tab: Int, CaseIterable { case submissions, flagged }

    struct State: Equatable {
        var tab: Tab = .submissions
        var submissions: [AdminSubmissionRow] = []
        var flagged: [AdminFlaggedReview] = []
        var isLoading = false
        var errorMessage: String?
    }

    var onChange: ((State) -> Void)?
    var onMessage: ((String) -> Void)?
    private(set) var state = State() { didSet { if state != oldValue { onChange?(state) } } }
    private let admin: AdminRepository
    private let notifier: DataChangeNotifier

    init(admin: AdminRepository, notifier: DataChangeNotifier) {
        self.admin = admin
        self.notifier = notifier
        notifier.subscribe(self) { [weak self] change in
            if change == .moderationChanged || change == .submissionsChanged { self?.load() }
        }
    }

    func select(_ tab: Tab) {
        state.tab = tab
        load()
    }

    func load() {
        state.isLoading = true
        Task {
            defer { state.isLoading = false }
            do {
                switch state.tab {
                case .submissions: state.submissions = try await admin.submissions()
                case .flagged: state.flagged = try await admin.flaggedReviews()
                }
                state.errorMessage = nil
            } catch {
                state.errorMessage = L10n.Errors.message(for: error)
            }
        }
    }

    func moderate(_ review: AdminFlaggedReview, status: ReviewStatus, reason: String) {
        Task {
            do {
                try await admin.moderateReview(id: review.id, status: status, reason: reason)
                onMessage?(L10n.Admin.done)
                notifier.publish(.moderationChanged)
            } catch {
                onMessage?(L10n.Errors.message(for: error))
            }
        }
    }
}

final class AdminSubmissionViewModel {
    struct State: Equatable {
        var detail: AdminSubmissionDetail?
        var mediaURLs: [URL] = []
        var isWorking = false
        var errorMessage: String?
        var finished = false
    }

    enum Prompt: Equatable { case likelyDuplicate }

    var onChange: ((State) -> Void)?
    var onPrompt: ((Prompt) -> Void)?
    private(set) var state = State() { didSet { if state != oldValue { onChange?(state) } } }
    let submissionID: UUID
    private let admin: AdminRepository
    private let venues: VenueRepository
    private let notifier: DataChangeNotifier

    init(submissionID: UUID, admin: AdminRepository, venues: VenueRepository, notifier: DataChangeNotifier) {
        self.submissionID = submissionID
        self.admin = admin
        self.venues = venues
        self.notifier = notifier
    }

    func load() async {
        do {
            let detail = try await admin.submissionDetail(id: submissionID)
            state.detail = detail
            let urls = await venues.signedURLs(paths: detail.mediaPaths, bucket: .venue)
            state.mediaURLs = detail.mediaPaths.compactMap { urls[$0] }
        } catch {
            state.errorMessage = L10n.Errors.message(for: error)
        }
    }

    func decide(_ decision: AdminSubmissionDecision) {
        guard !state.isWorking else { return }
        state.isWorking = true
        state.errorMessage = nil
        Task {
            defer { state.isWorking = false }
            do {
                try await admin.decide(submissionID: submissionID, decision: decision)
                notifier.publish(.moderationChanged)
                state.finished = true
            } catch BackendError.likelyDuplicate {
                onPrompt?(.likelyDuplicate)
            } catch {
                state.errorMessage = L10n.Errors.message(for: error)
            }
        }
    }
}
