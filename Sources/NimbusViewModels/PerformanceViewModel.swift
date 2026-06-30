import Foundation
import Observation
import NimbusKit

/// Drives the Performance screen: maintenance tasks (run via the helper) and a
/// read-only list of launch agents/daemons enumerated from disk. The app's own
/// launch-at-login is real; per-agent management is gated by the OS, so we link
/// into System Settings rather than fake a toggle.
@MainActor
@Observable
public final class PerformanceViewModel {
    public enum Kind: Sendable { case flushDNS, reindexSpotlight, flushFontCache, rebuildLaunchServices, clearQuickLook }
    public enum Status: Sendable, Equatable { case idle, running, done, failed(String) }

    public struct TaskItem: Identifiable, Sendable {
        public let id: String
        public let kind: Kind
        public let name: String
        public let desc: String
        public let recommended: Bool
        public let estimate: String
        public var selected: Bool
        public var status: Status
    }

    public struct AgentItem: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let source: String
    }

    public private(set) var tasks: [TaskItem]
    public private(set) var agents: [AgentItem] = []
    public var appLaunchAtLogin: Bool { didSet { applyLaunch() } }
    public private(set) var isRunning = false
    public private(set) var helperInstalled = false
    /// Raw OS error from a failed install (nil = none). The view localizes the
    /// surrounding sentence; this holds only the underlying message.
    public private(set) var helperErrorText: String?

    @ObservationIgnored private let service: PerformanceService
    @ObservationIgnored private let helper: PrivilegedHelperClient
    @ObservationIgnored private let loginItems = LoginItemsService()

    public init(helper: PrivilegedHelperClient = UnavailableHelperClient()) {
        self.helper = helper
        self.service = PerformanceService(helper: helper)
        self.appLaunchAtLogin = LoginItemsService().launchAtLoginState() == .enabled
        self.tasks = [
            TaskItem(id: "dns", kind: .flushDNS, name: "Очистити кеш DNS",
                     desc: "Допомагає, коли сайти не відкриваються після зміни мережі.",
                     recommended: true, estimate: "~2 с", selected: true, status: .idle),
            TaskItem(id: "spotlight", kind: .reindexSpotlight, name: "Перебудувати індекс Spotlight",
                     desc: "Виправляє неточний або повільний пошук.",
                     recommended: false, estimate: "5–30 хв", selected: false, status: .idle),
            TaskItem(id: "font", kind: .flushFontCache, name: "Скинути кеш шрифтів",
                     desc: "Усуває проблеми з відображенням шрифтів.",
                     recommended: false, estimate: "~5 с", selected: false, status: .idle),
            TaskItem(id: "ls", kind: .rebuildLaunchServices, name: "Перебудувати Launch Services",
                     desc: "Прибирає дублікати в меню «Відкрити за допомогою».",
                     recommended: true, estimate: "~10 с", selected: true, status: .idle),
            TaskItem(id: "ql", kind: .clearQuickLook, name: "Очистити кеш QuickLook",
                     desc: "Оновлює прев'ю файлів у Finder.",
                     recommended: false, estimate: "~3 с", selected: false, status: .idle),
        ]
    }

    public func load() {
        if agents.isEmpty { agents = Self.enumerateAgents() }
        Task { await refreshHelper() }
    }

    public func refreshHelper() async {
        helperInstalled = await helper.isInstalled()
    }

    /// Install the privileged helper (SMAppService). Requires a Developer ID build;
    /// on ad-hoc/local builds this surfaces a clear message instead of silently failing.
    public func installHelper() async {
        do {
            try await helper.install()
            helperErrorText = nil
            await refreshHelper()
        } catch {
            helperErrorText = error.localizedDescription
        }
    }

    public var selectedCount: Int { tasks.filter(\.selected).count }
    public var slowAgentCount: Int { agents.count }

    public func toggle(_ id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].selected.toggle()
    }

    public func runSelected() async {
        isRunning = true
        for index in tasks.indices where tasks[index].selected {
            tasks[index].status = .running
            let status = await run(tasks[index].kind)
            tasks[index].status = status
        }
        isRunning = false
    }

    public func openLoginItemsSettings() { loginItems.openLoginItemsSettings() }

    // MARK: - Private

    private func run(_ kind: Kind) async -> Status {
        switch kind {
        case .flushDNS:
            let r = await service.flushDNS()
            return r.succeeded ? .done : .failed(r.detail)
        case .reindexSpotlight:
            let r = await service.reindexSpotlight()
            return r.succeeded ? .done : .failed(r.detail)
        case .flushFontCache, .rebuildLaunchServices, .clearQuickLook:
            // These also require the privileged helper in a real build; without it
            // we report that honestly rather than pretend success.
            return .failed("Потрібен привілейований помічник.")
        }
    }

    private func applyLaunch() {
        do {
            if appLaunchAtLogin { try loginItems.enableLaunchAtLogin() }
            else { try loginItems.disableLaunchAtLogin() }
        } catch {}
    }

    private static func enumerateAgents() -> [AgentItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dirs: [(URL, String)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), "Користувацький агент"),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "Системний агент"),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "Системний демон"),
        ]
        var items: [AgentItem] = []
        for (dir, source) in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "plist" {
                let label = (try? PropertyListSerialization.propertyList(
                    from: Data(contentsOf: file), options: [], format: nil)) as? [String: Any]
                let name = (label?["Label"] as? String) ?? file.deletingPathExtension().lastPathComponent
                items.append(AgentItem(id: file.path, name: name, source: source))
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
