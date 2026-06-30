import Foundation

public struct ProcessMemoryUsage: Sendable, Identifiable, Equatable {
    public let id: Int32          // pid
    public let name: String
    public let residentBytes: Int64
}

/// Reads system health: live memory snapshots + the top memory-consuming
/// processes. Powers the menu-bar item. Strictly read-only — there is no
/// "free RAM" / `purge` button, by design.
///
/// Memory stats come from mach (`MemoryStatisticsReader`). Per-process memory
/// needs `task_for_pid`, which requires privilege for other processes, so top
/// consumers are read via `ps` (no privilege) instead.
public struct HealthMonitor: Sendable {
    private let memory = MemoryStatisticsReader()
    private let runner = ProcessRunner()

    public init() {}

    public func memorySnapshot() -> MemorySnapshot { memory.snapshot() }

    /// A live stream of snapshots at `interval` seconds, for the menu bar.
    public func memoryStream(interval: Duration = .seconds(2)) -> AsyncStream<MemorySnapshot> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield(memory.snapshot())
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func topMemoryConsumers(limit: Int = 5) async -> [ProcessMemoryUsage] {
        // -m sorts by memory (resident size) descending, so the top N are first.
        guard let result = try? await runner.run("/bin/ps", ["-axo", "pid=,rss=,comm=", "-m"]),
              result.status == 0
        else { return [] }

        var usages: [ProcessMemoryUsage] = []
        for line in result.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "<pid> <rssKiB> <command path...>"
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let rssKiB = Int64(parts[1])
            else { continue }
            let name = URL(fileURLWithPath: String(parts[2])).lastPathComponent
            usages.append(ProcessMemoryUsage(id: pid, name: name, residentBytes: rssKiB * 1024))
            if usages.count >= limit { break }
        }
        return usages
    }
}
