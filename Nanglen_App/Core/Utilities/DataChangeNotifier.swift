import Foundation

/// Data changes that other screens should react to.
enum DataChange: Equatable {
    case favoritesChanged(venueID: UUID)
    case reviewSubmitted(venueID: UUID)
    case submissionsChanged
    case moderationChanged
    case sessionChanged
    case cacheCleared
}

/// Tiny main-actor event bus so screens stay in sync (e.g. saving on the
/// detail screen updates Saved and Explore) without singletons.
/// Subscribers are held weakly and pruned automatically once deallocated.
final class DataChangeNotifier {
    private struct Entry {
        weak var owner: AnyObject?
        let handler: (DataChange) -> Void
    }

    private var entries: [Entry] = []

    func subscribe(_ owner: AnyObject, handler: @escaping (DataChange) -> Void) {
        entries.removeAll { $0.owner == nil }
        entries.append(Entry(owner: owner, handler: handler))
    }

    func publish(_ change: DataChange) {
        entries.removeAll { $0.owner == nil }
        entries.forEach { $0.handler(change) }
    }
}
