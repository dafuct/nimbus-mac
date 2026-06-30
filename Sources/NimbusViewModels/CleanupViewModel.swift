import Foundation
import Observation
import NimbusKit

/// Drives the Cleanup screen. Auto-selectable items start ticked; manual ones
/// don't. Removal is Trash-by-default through the shared `Remover`.
@MainActor
@Observable
public final class CleanupViewModel {
    public enum Phase: Sendable {
        case idle
        case scanning(ScanProgress)
        case loaded([CleanupGroup])
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var selection = SelectionStore<CleanupItem>()
    public private(set) var lastRemoval: RemovalReport?

    private let scanner: CleanupScanner
    private let remover: Remover
    private var scanTask: Task<Void, Never>?

    public init(engine: SafetyRuleEngine, remover: Remover = Remover()) {
        self.scanner = CleanupScanner(engine: engine)
        self.remover = remover
    }

    public var groups: [CleanupGroup] {
        if case let .loaded(groups) = phase { return groups }
        return []
    }

    private var allItems: [CleanupItem] { groups.flatMap(\.items) }

    public var reclaimableSelected: Int64 {
        selection.reclaimableBytes(over: allItems)
    }

    public func scan() {
        cancel()
        phase = .scanning(.zero)
        scanTask = Task { [weak self] in
            do {
                let groups = try await self?.scanner.scan { progress in
                    Task { @MainActor [weak self] in
                        if case .scanning = self?.phase { self?.phase = .scanning(progress) }
                    }
                } ?? []
                self?.phase = .loaded(groups)
                self?.selectAutoDefaults()
            } catch let error as NimbusError where error.isCancellation {
                self?.phase = .idle
            } catch is CancellationError {
                self?.phase = .idle
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    public func cancel() { scanTask?.cancel(); scanTask = nil }

    /// Pre-tick only the auto-selectable items; manual ones require opt-in.
    public func selectAutoDefaults() {
        var store = SelectionStore<CleanupItem>()
        for item in allItems where item.autoSelected { store.set(item.id, selected: true) }
        selection = store
    }

    public func toggle(_ item: CleanupItem) { selection.toggle(item.id) }

    public func dismissReport() { lastRemoval = nil }

    // MARK: Expandable categories

    public enum GroupSelection: Sendable { case all, none, some }

    public private(set) var expanded: Set<String> = []

    public func isExpanded(_ group: CleanupGroup) -> Bool { expanded.contains(group.id) }

    public func toggleExpand(_ group: CleanupGroup) {
        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
    }

    public func selectedCount(in group: CleanupGroup) -> Int {
        group.items.filter { selection.isSelected($0.id) }.count
    }

    public func selectionState(_ group: CleanupGroup) -> GroupSelection {
        let n = selectedCount(in: group)
        if n == 0 { return .none }
        if n == group.items.count { return .all }
        return .some
    }

    public func toggleCategory(_ group: CleanupGroup) {
        let target = selectionState(group) != .all
        for item in group.items { selection.set(item.id, selected: target) }
    }

    public func removeSelected(permanently: Bool = false) async {
        let items = selection.selectedItems(from: allItems)
            .map { RemovalItem(url: $0.url, bytes: $0.bytes) }
        guard !items.isEmpty else { return }
        lastRemoval = await remover.remove(
            items,
            mode: permanently ? .permanentDelete : .trash,
            allowPermanent: permanently
        )
        scan()
    }
}
