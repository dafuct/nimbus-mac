import Foundation

/// Maintenance tasks. Unprivileged work runs directly; anything needing root is
/// delegated to the privileged helper. Each task reports a typed result so the UI
/// can show success/failure without parsing strings.
public struct PerformanceService: Sendable {
    private let helper: PrivilegedHelperClient
    private let runner = ProcessRunner()

    public init(helper: PrivilegedHelperClient = UnavailableHelperClient()) {
        self.helper = helper
    }

    public enum Task: String, Sendable, CaseIterable {
        case flushDNS = "Flush DNS Cache"
        case reindexSpotlight = "Rebuild Spotlight Index"
        case purgeUserCaches = "Clear User Caches"  // example of an unprivileged maintenance op
    }

    public struct TaskResult: Sendable {
        public let task: Task
        public let succeeded: Bool
        public let detail: String
    }

    /// Flush DNS — privileged. Routed through the helper.
    public func flushDNS() async -> TaskResult {
        do {
            try await helper.flushDNSCache()
            return TaskResult(task: .flushDNS, succeeded: true, detail: "DNS cache flushed.")
        } catch {
            return TaskResult(task: .flushDNS, succeeded: false, detail: error.localizedDescription)
        }
    }

    /// Reindex Spotlight on the boot volume — privileged.
    public func reindexSpotlight(volume: String = "/") async -> TaskResult {
        do {
            try await helper.reindexSpotlight(volume: volume)
            return TaskResult(task: .reindexSpotlight, succeeded: true, detail: "Spotlight reindex started for \(volume).")
        } catch {
            return TaskResult(task: .reindexSpotlight, succeeded: false, detail: error.localizedDescription)
        }
    }
}
