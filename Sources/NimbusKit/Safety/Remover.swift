import Foundation

public enum DisposalMode: Sendable, Equatable {
    /// Reversible: move to the Trash. The default for everything.
    case trash
    /// Irreversible: delete outright. Requires a separate explicit confirmation.
    case permanentDelete
}

/// One thing to remove, with its known on-disk size so reclaimed totals are exact.
public struct RemovalItem: Sendable, Equatable {
    public let url: URL
    public let bytes: Int64
    public init(url: URL, bytes: Int64) {
        self.url = url
        self.bytes = bytes
    }
}

public struct RemovalOutcome: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case trashed(URL?)     // moved to Trash (resulting URL if known)
        case deleted           // permanently removed
        case wouldRemove       // dry-run: nothing changed
        case refused(String)   // blocked by the guard / missing confirmation
        case failed(String)    // OS error
    }
    public let url: URL
    public let bytes: Int64
    public let kind: Kind

    public var didReclaim: Bool {
        switch kind {
        case .trashed, .deleted: return true
        case .wouldRemove, .refused, .failed: return false
        }
    }
}

public struct RemovalReport: Sendable {
    public let outcomes: [RemovalOutcome]
    public let dryRun: Bool

    public var reclaimedBytes: Int64 {
        outcomes.reduce(0) { $0 + ($1.didReclaim ? $1.bytes : 0) }
    }
    /// In dry-run, the bytes that *would* be reclaimed.
    public var projectedBytes: Int64 {
        outcomes.reduce(0) { sum, o in
            switch o.kind {
            case .trashed, .deleted, .wouldRemove: return sum + o.bytes
            case .refused, .failed: return sum
            }
        }
    }
    public var refused: [RemovalOutcome] { outcomes.filter { if case .refused = $0.kind { return true }; return false } }
    public var failed: [RemovalOutcome] { outcomes.filter { if case .failed = $0.kind { return true }; return false } }
}

/// The single destructive engine. Every module routes removals through here, so
/// the safety guarantees live in exactly one place:
/// - the `CriticalPathGuard` can veto any path, even a user-confirmed one;
/// - permanent deletion is refused unless explicitly confirmed (`allowPermanent`);
/// - `dryRun` reports what *would* happen and changes nothing;
/// - Trash (reversible) is the default disposal.
public struct Remover: Sendable {
    private let guardian: CriticalPathGuard
    private let dryRun: Bool

    public init(guardian: CriticalPathGuard = CriticalPathGuard(), dryRun: Bool = false) {
        self.guardian = guardian
        self.dryRun = dryRun
    }

    public func remove(
        _ items: [RemovalItem],
        mode: DisposalMode = .trash,
        allowPermanent: Bool = false,
        onProgress: ProgressHandler? = nil
    ) async -> RemovalReport {
        let fm = FileManager.default
        var outcomes: [RemovalOutcome] = []
        var progress = ScanProgress.zero

        for item in items {
            if Task.isCancelled { break }

            let kind = outcomeKind(for: item, mode: mode, allowPermanent: allowPermanent, fm: fm)
            outcomes.append(RemovalOutcome(url: item.url, bytes: item.bytes, kind: kind))

            progress.filesSeen += 1
            if case .trashed = kind { progress.bytesSeen += item.bytes }
            if case .deleted = kind { progress.bytesSeen += item.bytes }
            progress.currentPath = item.url.path
            onProgress?(progress)
        }

        return RemovalReport(outcomes: outcomes, dryRun: dryRun)
    }

    private func outcomeKind(
        for item: RemovalItem,
        mode: DisposalMode,
        allowPermanent: Bool,
        fm: FileManager
    ) -> RemovalOutcome.Kind {
        if guardian.isProtected(item.url) {
            return .refused("Protected system path.")
        }
        if mode == .permanentDelete && !allowPermanent {
            return .refused("Permanent deletion not confirmed.")
        }
        if dryRun {
            return .wouldRemove
        }

        do {
            switch mode {
            case .trash:
                var resulting: NSURL?
                try fm.trashItem(at: item.url, resultingItemURL: &resulting)
                return .trashed(resulting as URL?)
            case .permanentDelete:
                try fm.removeItem(at: item.url)
                return .deleted
            }
        } catch {
            return .failed((error as NSError).localizedDescription)
        }
    }
}
