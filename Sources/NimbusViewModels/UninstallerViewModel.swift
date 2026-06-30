import Foundation
import Observation
import NimbusKit

/// Drives the Uninstaller: real installed apps + their `~/Library` leftovers,
/// removed (with leftovers) through the shared `Remover`. App bundle sizes are
/// computed lazily in the background; leftovers resolve on selection.
@MainActor
@Observable
public final class UninstallerViewModel {
    public struct Row: Identifiable, Sendable {
        public let app: InstalledApp
        public var sizeBytes: Int64?
        public let lastUsed: Date?
        public var id: String { app.id }
        public var isRare: Bool {
            guard let lastUsed else { return false }
            return Date().timeIntervalSince(lastUsed) > 120 * 24 * 3600
        }
        public var initials: String {
            String(app.name.prefix(1)).uppercased()
        }
    }

    public enum Filter: String, Sendable, CaseIterable { case all, rare, large }

    public var query: String = ""
    public var filter: Filter = .all
    public private(set) var rows: [Row] = []
    public private(set) var selectedID: String?
    public private(set) var leftovers: [Leftover] = []
    public private(set) var selection = SelectionStore<Leftover>()
    public private(set) var lastRemoval: RemovalReport?
    public private(set) var isResolving = false

    @ObservationIgnored private let uninstaller = Uninstaller()
    @ObservationIgnored private var sizingTask: Task<Void, Never>?

    public init() {}

    public func load() {
        rows = uninstaller.installedApps().map {
            Row(app: $0, sizeBytes: nil, lastUsed: Self.accessDate($0.url))
        }
        if selectedID == nil, let first = filteredRows.first { Task { await select(first.id) } }
        startBackgroundSizing()
    }

    public var filteredRows: [Row] {
        var result = rows
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { result = result.filter { $0.app.name.lowercased().contains(q) } }
        switch filter {
        case .all: result.sort { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
        case .rare: result = result.filter(\.isRare)
        case .large: result.sort { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        }
        return result
    }

    public var rareCount: Int { rows.filter(\.isRare).count }
    public var total: Int { rows.count }

    public var selectedRow: Row? { rows.first { $0.id == selectedID } }

    public func select(_ id: String) async {
        selectedID = id
        guard let row = rows.first(where: { $0.id == id }) else { return }
        isResolving = true
        let resolved = await uninstaller.leftovers(for: row.app)
        leftovers = resolved
        selection.selectAll(resolved) // pre-select everything; app bundle always goes
        isResolving = false
    }

    public func toggle(_ leftover: Leftover) { selection.toggle(leftover.id) }

    public var selectedTotal: Int64 { selection.reclaimableBytes(over: leftovers) }

    public func uninstall(permanently: Bool = false) async {
        let chosen = selection.selectedItems(from: leftovers)
        guard !chosen.isEmpty else { return }
        lastRemoval = await uninstaller.uninstall(chosen, permanently: permanently)
        // Refresh the list (the app may be gone now).
        load()
    }

    // MARK: - Background sizing

    private func startBackgroundSizing() {
        sizingTask?.cancel()
        let apps = rows.map(\.app)
        sizingTask = Task { [weak self] in
            for app in apps {
                if Task.isCancelled { return }
                let size = await Self.bundleSize(app.url)
                await MainActor.run {
                    guard let self else { return }
                    if let idx = self.rows.firstIndex(where: { $0.id == app.id }) {
                        self.rows[idx].sizeBytes = size
                    }
                }
            }
        }
    }

    private static func bundleSize(_ url: URL) async -> Int64 {
        let entries = (try? await FileSystemScanner.collect(root: url, options: ScanOptions(skipPackages: false))) ?? []
        return entries.reduce(0) { $0 + $1.size }
    }

    private static func accessDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
    }
}
