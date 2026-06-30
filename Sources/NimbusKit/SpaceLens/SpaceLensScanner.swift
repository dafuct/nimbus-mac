import Foundation

/// Space Lens: scan a root (no privileges required) and produce an aggregated
/// disk-usage tree ready for the treemap. Pure orchestration over the shared
/// `FileSystemScanner` + `DiskUsageTreeBuilder` — it adds no traversal of its own.
public struct SpaceLensScanner: Sendable {

    public init() {}

    /// Scan `root`, reporting progress, and return the aggregated tree.
    /// Honors cancellation via the calling `Task`.
    public func scan(
        root: URL,
        exclusions: ExclusionMatcher = .empty,
        applyDefaultExclusions: Bool = true,
        onProgress: ProgressHandler? = nil
    ) async throws -> DiskUsageNode {
        var options = ScanOptions()
        options.skipPackages = false      // size .app bundles fully
        options.includeHidden = true
        // Default home scan skips network-faulting / transient trees for speed;
        // an explicitly picked folder is shown in full.
        options.exclusions = applyDefaultExclusions
            ? DefaultExclusions.spaceLens().merging(exclusions)
            : exclusions

        let entries = try await FileSystemScanner.collect(
            root: root,
            options: options,
            onProgress: onProgress
        )
        try Task.checkCancellation()
        return DiskUsageTreeBuilder.build(root: root, entries: entries)
    }

    /// Common scan roots offered in the UI (Home is the privilege-free default).
    public static var suggestedRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home]
    }
}
