import Foundation
import os

/// Retries photos whose review/submission was published while their upload failed offline.
///
/// Runs at launch and after every sign-in (both publish `.sessionChanged`) and when the app returns to
/// the foreground. Only the current user's items whose `next_attempt_at` has passed are sent.
/// - Transient failures (offline, rate limit, server/unknown error) back off exponentially, at most `maxAttempts` tries.
/// - Permanent failures (4xx-type answers: not found, invalid input, review removed, …) are dropped and logged.
/// - Success removes the row and file and publishes a `DataChange` so screens refresh.
final class PendingUploadService {
    static let maxAttempts = 5
    /// Delay before retry n (0-based) is `baseDelay * 2^n`: 30 s, 1 min, 2 min, 4 min.
    static let baseDelay: TimeInterval = 30

    nonisolated struct RunSummary: Hashable, Sendable {
        var uploaded = 0
        var retrying = 0
        var dropped = 0
    }

    private let store: PendingUploadStore
    private let reviews: ReviewRemote
    private let submissions: SubmissionRemote
    private let currentUserID: () async -> UUID?
    private let notifier: DataChangeNotifier
    private let clock: () -> Date
    private var running: Task<RunSummary, Never>?
    private let logger = Logger(subsystem: "Mach.Nanglen-App", category: "PendingUploads")

    init(store: PendingUploadStore, reviews: ReviewRemote, submissions: SubmissionRemote,
         userID: @escaping () async -> UUID?, notifier: DataChangeNotifier, clock: @escaping () -> Date = { Date() }) {
        self.store = store
        self.reviews = reviews
        self.submissions = submissions
        currentUserID = userID
        self.notifier = notifier
        self.clock = clock
        notifier.subscribe(self) { [weak self] change in
            if case .sessionChanged = change { self?.trigger() }
        }
    }

    /// Fire-and-forget run (launch, foreground, sign-in).
    func trigger() {
        Task { await run() }
    }

    /// Sends every due item once. Concurrent calls share the same pass.
    @discardableResult
    func run() async -> RunSummary {
        if let running { return await running.value }
        let task = Task { await performRun() }
        running = task
        let summary = await task.value
        running = nil
        return summary
    }

    private func performRun() async -> RunSummary {
        var summary = RunSummary()
        guard let userID = await currentUserID(),
              let due = try? await store.due(userID: userID, now: clock()), !due.isEmpty else { return summary }
        var changes: [DataChange] = []
        for upload in due {
            if Task.isCancelled { break }
            switch await send(upload) {
            case .uploaded(let change):
                summary.uploaded += 1
                if !changes.contains(change) { changes.append(change) }
            case .retrying: summary.retrying += 1
            case .dropped: summary.dropped += 1
            }
        }
        changes.forEach(notifier.publish)
        return summary
    }

    private enum Outcome {
        case uploaded(DataChange)
        case retrying
        case dropped
    }

    private func send(_ upload: PendingUpload) async -> Outcome {
        guard let photo = store.photo(for: upload) else {
            logger.error("Dropping queued \(upload.kind.rawValue, privacy: .public) \(upload.id, privacy: .public): file missing or unreadable")
            await store.remove(upload)
            return .dropped
        }
        do {
            let change: DataChange
            switch upload.kind {
            case .reviewPhoto:
                try await reviews.uploadReviewPhoto(revisionID: upload.targetID, photo: photo)
                change = upload.venueID.map { .reviewSubmitted(venueID: $0) } ?? .submissionsChanged
            case .submissionPhoto:
                try await submissions.uploadSubmissionPhoto(submissionID: upload.targetID, photo: photo)
                change = .submissionsChanged
            }
            await store.remove(upload)
            return .uploaded(change)
        } catch is CancellationError {
            return .retrying // not an attempt: the item stays as it was
        } catch {
            let attempts = upload.attempts + 1
            guard Self.isTransient(error), attempts < Self.maxAttempts else {
                logger.error("""
                    Giving up on queued \(upload.kind.rawValue, privacy: .public) \(upload.id, privacy: .public) \
                    after \(attempts) attempt(s): \(String(describing: error), privacy: .public)
                    """)
                await store.remove(upload)
                return .dropped
            }
            let next = clock().addingTimeInterval(Self.backoff(afterAttempts: upload.attempts))
            try? await store.markAttempt(upload, error: String(describing: error), nextAttemptAt: next)
            return .retrying
        }
    }

    /// Delay after the `attempts`-th failure (0-based): 30 s × 2ⁿ.
    static func backoff(afterAttempts attempts: Int) -> TimeInterval {
        baseDelay * pow(2, Double(max(0, attempts)))
    }

    /// Worth retrying: offline, rate-limited, server-side or unknown errors. Everything the server
    /// rejected on purpose (missing revision/submission, invalid input, auth/role, removed review) is permanent.
    static func isTransient(_ error: Error) -> Bool {
        if NetworkFailure.isOffline(error) { return true }
        guard let backend = error as? BackendError else { return true }
        switch backend {
        case .rateLimited, .server: return true
        default: return false
        }
    }
}
