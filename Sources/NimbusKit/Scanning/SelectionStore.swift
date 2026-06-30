import Foundation

/// Anything a user can tick for removal: a duplicate file, a cleanup item, an
/// uninstaller leftover. Carrying `removalBytes` lets the shared selection store
/// compute "X selected, Y reclaimable" identically everywhere.
public protocol Selectable: Identifiable, Sendable {
    var removalBytes: Int64 { get }
}

/// Reusable selection state. Modules differ only in *what* is selectable; the
/// toggle/select-all/clear/reclaimable math is shared here rather than copied
/// into each view model.
public struct SelectionStore<Item: Selectable>: Sendable where Item.ID: Sendable {
    public private(set) var selectedIDs: Set<Item.ID> = []

    public init(selectedIDs: Set<Item.ID> = []) {
        self.selectedIDs = selectedIDs
    }

    public func isSelected(_ id: Item.ID) -> Bool { selectedIDs.contains(id) }

    public mutating func toggle(_ id: Item.ID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    public mutating func set(_ id: Item.ID, selected: Bool) {
        if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
    }

    public mutating func selectAll(_ items: [Item]) {
        selectedIDs = Set(items.map(\.id))
    }

    public mutating func clear() { selectedIDs.removeAll() }

    /// Replace `from` with the smart default: in each duplicate/similar group the
    /// caller passes, keep one and select the rest. Generic via a grouping closure.
    public mutating func selectAllButFirst<G>(in groups: [G], items: (G) -> [Item]) {
        selectedIDs.removeAll()
        for group in groups {
            let members = items(group)
            guard members.count > 1 else { continue }
            for member in members.dropFirst() { selectedIDs.insert(member.id) }
        }
    }

    public func reclaimableBytes(over items: [Item]) -> Int64 {
        items.reduce(0) { $0 + (selectedIDs.contains($1.id) ? $1.removalBytes : 0) }
    }

    public func selectedItems(from items: [Item]) -> [Item] {
        items.filter { selectedIDs.contains($0.id) }
    }

    public var count: Int { selectedIDs.count }
    public var isEmpty: Bool { selectedIDs.isEmpty }
}
