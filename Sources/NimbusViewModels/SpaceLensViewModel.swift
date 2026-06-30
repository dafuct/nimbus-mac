import Foundation
import Observation
import NimbusKit

/// Drives the Space Lens screen. Holds the scan lifecycle and the loaded tree;
/// the SwiftUI view is a pure projection of `phase`. No traversal logic here — it
/// delegates to `SpaceLensScanner`.
@MainActor
@Observable
public final class SpaceLensViewModel {
    public enum Phase: Sendable {
        case idle
        case scanning(ScanProgress)
        case loaded(DiskUsageNode)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public var root: URL
    public var exclusions: ExclusionMatcher

    private let scanner = SpaceLensScanner()
    private let remover = Remover()
    private var scanTask: Task<Void, Never>?
    public private(set) var lastRemoval: RemovalReport?

    public init(
        root: URL = SpaceLensScanner.suggestedRoots.first ?? FileManager.default.homeDirectoryForCurrentUser,
        exclusions: ExclusionMatcher = .empty
    ) {
        self.root = root
        self.exclusions = exclusions
    }

    /// True once the user picks a specific folder — then we scan it in full
    /// (no default exclusions) since they explicitly asked to inspect it.
    public private(set) var userPickedRoot = false

    public var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    /// Point Space Lens at a user-chosen folder and scan it in full.
    public func setRoot(_ url: URL) {
        root = url
        userPickedRoot = true
    }

    public func scan() {
        cancel()
        phase = .scanning(.zero)
        let root = self.root
        let exclusions = self.exclusions
        let applyDefaults = !userPickedRoot
        scanTask = Task { [weak self] in
            do {
                let tree = try await self?.scanner.scan(root: root, exclusions: exclusions, applyDefaultExclusions: applyDefaults) { progress in
                    Task { @MainActor [weak self] in
                        if self?.isScanning == true { self?.phase = .scanning(progress) }
                    }
                }
                if let tree { self?.phase = .loaded(tree) }
            } catch let error as NimbusError where error.isCancellation {
                self?.phase = .idle
            } catch is CancellationError {
                self?.phase = .idle
            } catch {
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    public func cancel() {
        scanTask?.cancel()
        scanTask = nil
    }

    /// Move a selected node to the Trash (reversible), then rescan.
    public func trash(_ node: DiskUsageNode) async {
        lastRemoval = await remover.remove([RemovalItem(url: node.url, bytes: node.size)])
        scan()
    }

    public func dismissReport() { lastRemoval = nil }
}
