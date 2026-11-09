import UIKit

/// Diffable data source for the Explore list. Items are venue ids; content
/// changes (new reviews, favorites) are applied with `reconfigureItems` so
/// cards update in place without flicker.
final class ExploreDataSource {
    typealias Section = ExploreViewModel.Section

    private final class Store {
        var items: [UUID: VenueCardItem] = [:]
    }

    private let store = Store()
    private let diffable: UITableViewDiffableDataSource<ExploreViewModel.SectionKind, UUID>
    private(set) var sections: [Section] = []

    init(tableView: UITableView) {
        let store = store
        diffable = UITableViewDiffableDataSource(tableView: tableView) { tableView, indexPath, id in
            let cell = tableView.dequeueReusableCell(withIdentifier: PlaceCardCell.reuseIdentifier, for: indexPath)
            if let card = cell as? PlaceCardCell, let item = store.items[id] {
                card.configure(with: item)
            }
            return cell
        }
        diffable.defaultRowAnimation = .fade
    }

    func apply(_ sections: [Section], animated: Bool) {
        let previous = store.items
        var seen = Set<UUID>()
        var unique: [Section] = []
        var items: [UUID: VenueCardItem] = [:]
        for var section in sections {
            section.items = section.items.filter { seen.insert($0.id).inserted }
            section.items.forEach { items[$0.id] = $0 }
            unique.append(section)
        }
        store.items = items
        self.sections = unique

        var snapshot = NSDiffableDataSourceSnapshot<ExploreViewModel.SectionKind, UUID>()
        for section in unique {
            snapshot.appendSections([section.kind])
            snapshot.appendItems(section.items.map(\.id), toSection: section.kind)
        }
        let changed = snapshot.itemIdentifiers.filter { id in
            guard let old = previous[id] else { return false }
            return old != items[id]
        }
        snapshot.reconfigureItems(changed)
        diffable.apply(snapshot, animatingDifferences: animated)
    }

    func item(at indexPath: IndexPath) -> VenueCardItem? {
        diffable.itemIdentifier(for: indexPath).flatMap { store.items[$0] }
    }

    func section(at index: Int) -> Section? {
        guard let kind = diffable.sectionIdentifier(for: index) else { return nil }
        return sections.first { $0.kind == kind }
    }
}
