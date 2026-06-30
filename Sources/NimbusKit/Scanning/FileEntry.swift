import Foundation

/// One file discovered during a scan. Value type, `Sendable`, safe to ferry
/// across concurrency domains. Directories are *not* emitted as entries — Space
/// Lens reconstructs the tree by folding file paths (see `DiskUsageTreeBuilder`),
/// which keeps the traversal a single source of truth for every module.
public struct FileEntry: Sendable, Hashable {
    public let url: URL
    /// On-disk allocated size in bytes (`.totalFileAllocatedSize`), falling back
    /// to logical size. This is what actually frees up when removed.
    public let size: Int64
    public let isSymbolicLink: Bool
    public let isPackage: Bool
    public let modificationDate: Date?

    public init(
        url: URL,
        size: Int64,
        isSymbolicLink: Bool = false,
        isPackage: Bool = false,
        modificationDate: Date? = nil
    ) {
        self.url = url
        self.size = size
        self.isSymbolicLink = isSymbolicLink
        self.isPackage = isPackage
        self.modificationDate = modificationDate
    }
}

/// Knobs shared by every scan. `exclusions` is the user-editable list, honored
/// identically across modules.
public struct ScanOptions: Sendable {
    public var includeHidden: Bool
    public var followSymlinks: Bool
    /// When true, `.app`/`.bundle`/etc. are skipped wholesale (never descended,
    /// never emitted). Duplicates/Photos/Cleanup set this so they never touch an
    /// app's internals; Space Lens sets it false to size everything.
    public var skipPackages: Bool
    public var exclusions: ExclusionMatcher
    /// Skip files smaller than this (duplicates/photos don't care about tiny files).
    public var minFileSize: Int64

    public init(
        includeHidden: Bool = true,
        followSymlinks: Bool = false,
        skipPackages: Bool = true,
        exclusions: ExclusionMatcher = .empty,
        minFileSize: Int64 = 0
    ) {
        self.includeHidden = includeHidden
        self.followSymlinks = followSymlinks
        self.skipPackages = skipPackages
        self.exclusions = exclusions
        self.minFileSize = minFileSize
    }
}
