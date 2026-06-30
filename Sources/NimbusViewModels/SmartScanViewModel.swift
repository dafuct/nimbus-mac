import Foundation
import Observation
import NimbusKit

/// Orchestrates a Smart Scan. Runs the *cheap, bounded* modules for real
/// (Cleanup reclaimable, installed/rare apps, memory health) and aggregates them
/// into the headline + result tiles. The expensive full-disk modules (Duplicates,
/// large-file Space Lens) are surfaced as "review" tiles that open the module to
/// scan on demand, rather than forcing a multi-minute home walk here.
@MainActor
@Observable
public final class SmartScanViewModel {
    public enum Phase: Sendable { case idle, scanning, done }

    public private(set) var phase: Phase = .idle
    public private(set) var currentStage: String = ""

    // Real results
    public private(set) var reclaimableCleanup: Int64 = 0
    public private(set) var cleanupItemCount: Int = 0
    public private(set) var totalApps: Int = 0
    public private(set) var rareApps: Int = 0
    public private(set) var recommendedTasks: Int = 2
    public private(set) var healthLabel: String = "—"
    public private(set) var healthPressure: MemoryPressureLevel = .normal

    @ObservationIgnored private let engine: SafetyRuleEngine
    @ObservationIgnored private let appsProvider = InstalledAppsProvider()
    @ObservationIgnored private let monitor = HealthMonitor()
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(engine: SafetyRuleEngine) {
        self.engine = engine
    }

    /// Total surfaced as "Знайдено X" — currently the safely-reclaimable Cleanup total.
    public var totalFound: Int64 { reclaimableCleanup }

    public func run() {
        task?.cancel()
        task = Task { [weak self] in await self?.perform() }
    }

    public func cancel() { task?.cancel(); task = nil; phase = .idle }

    func perform() async {
        phase = .scanning

        // 1) Cleanup — real, fast (known base dirs).
        currentStage = "Системний мотлох"
        let scanner = CleanupScanner(engine: engine)
        let groups = (try? await scanner.scan()) ?? []
        reclaimableCleanup = groups.reduce(0) { $0 + $1.totalBytes }
        cleanupItemCount = groups.reduce(0) { $0 + $1.items.count }

        if Task.isCancelled { phase = .idle; return }

        // 2) Apps — real, fast.
        currentStage = "Застосунки"
        let apps = appsProvider.installedApps()
        totalApps = apps.count
        let now = Date()
        rareApps = apps.filter { app in
            guard let used = (try? app.url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
            else { return false }
            return now.timeIntervalSince(used) > 120 * 24 * 3600
        }.count

        // 3) Health — real snapshot.
        currentStage = "Стан системи"
        let snapshot = monitor.memorySnapshot()
        healthPressure = snapshot.pressure
        healthLabel = Self.label(snapshot.pressure)

        if Task.isCancelled { phase = .idle; return }
        phase = .done
    }

    private static func label(_ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: return "Добре"
        case .warning: return "Помірний"
        case .critical: return "Високий"
        }
    }
}
