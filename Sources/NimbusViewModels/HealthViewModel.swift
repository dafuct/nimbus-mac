import Foundation
import Observation
import NimbusKit

/// Drives the menu-bar Health item: a live memory snapshot + top consumers.
/// Read-only by design — there is no "free RAM" action.
@MainActor
@Observable
public final class HealthViewModel {
    public private(set) var snapshot: MemorySnapshot?
    public private(set) var topConsumers: [ProcessMemoryUsage] = []

    private let monitor = HealthMonitor()
    private var streamTask: Task<Void, Never>?
    private var consumersTask: Task<Void, Never>?

    public init() {}

    public func start(interval: Duration = .seconds(2)) {
        stop()
        streamTask = Task { [weak self] in
            guard let stream = self?.monitor.memoryStream(interval: interval) else { return }
            for await snapshot in stream {
                guard let self else { break } // VM gone -> stop consuming
                self.snapshot = snapshot
            }
        }
        consumersTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                self.topConsumers = await self.monitor.topMemoryConsumers(limit: 5)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    public func stop() {
        streamTask?.cancel(); streamTask = nil
        consumersTask?.cancel(); consumersTask = nil
    }
}
