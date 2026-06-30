import Foundation

/// The single file-system traversal in the whole app. Every module — Space Lens,
/// Duplicates, Similar Photos, Cleanup, Uninstaller — consumes this stream rather
/// than re-implementing a walk. It is I/O-bound, so it stays in Swift/FileManager
/// (Rust would not speed it up); CPU-bound work downstream is what goes to Rust.
///
/// Behavior:
/// - Emits *files only* (directories are folded back into a tree by Space Lens).
/// - Iterative DFS, so deep trees don't blow the stack.
/// - Cancellation-aware: honors the consuming `Task`'s cancellation between every
///   entry, so long scans stop promptly.
/// - Resilient: an unreadable *sub*directory (e.g. lacking Full Disk Access) is
///   skipped, not fatal. Only an unreadable *root* throws.
public enum FileSystemScanner {

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
    ]

    /// Stream every file under `root` honoring `options`.
    public static func entries(
        root: URL,
        options: ScanOptions = .init()
    ) -> AsyncThrowingStream<FileEntry, Error> {
        AsyncThrowingStream(FileEntry.self, bufferingPolicy: .bufferingNewest(4096)) { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    try await walk(root: root, options: options) { entry in
                        continuation.yield(entry)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: NimbusError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Collect all entries into an array (convenience for callers that need the
    /// full set before processing, e.g. the duplicate size-bucketing pass).
    public static func collect(
        root: URL,
        options: ScanOptions = .init(),
        onProgress: ProgressHandler? = nil
    ) async throws -> [FileEntry] {
        var result: [FileEntry] = []
        var progress = ScanProgress.zero
        for try await entry in entries(root: root, options: options) {
            result.append(entry)
            progress.filesSeen += 1
            progress.bytesSeen += entry.size
            progress.currentPath = entry.url.path
            if let onProgress, progress.filesSeen % 256 == 0 {
                onProgress(progress)
            }
        }
        onProgress?(progress)
        return result
    }

    // MARK: - Core walk

    static func walk(
        root: URL,
        options: ScanOptions,
        emit: (FileEntry) async -> Void
    ) async throws {
        let fm = FileManager.default
        let keySet = Set(resourceKeys)
        var dirOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { dirOptions.insert(.skipsHiddenFiles) }

        // Resolve the root once so every emitted path is canonical (e.g. the
        // /var -> /private/var firmlink), keeping exclusion matching a cheap
        // string compare and emitted paths consistent with `contentsOfDirectory`.
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var stack: [URL] = [canonicalRoot]
        var counter = 0

        while let dir = stack.popLast() {
            try Task.checkCancellation()

            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: FileSystemScanner.resourceKeys,
                    options: dirOptions
                )
            } catch {
                if dir == canonicalRoot {
                    throw NimbusError.rootUnreadable(
                        root,
                        underlying: (error as NSError).localizedDescription
                    )
                }
                continue // unreadable subdirectory — skip, keep scanning
            }

            for child in children {
                try Task.checkCancellation()
                counter += 1
                if counter % 512 == 0 { await Task.yield() }

                if options.exclusions.shouldExclude(child) { continue }

                let rv = try? child.resourceValues(forKeys: keySet)
                let isSymlink = rv?.isSymbolicLink ?? false
                if isSymlink && !options.followSymlinks { continue } // avoid cycles/double-count

                let isDirectory = rv?.isDirectory ?? false
                let isPackage = rv?.isPackage ?? false

                if isDirectory {
                    if isPackage && options.skipPackages { continue }
                    stack.append(child)
                    continue
                }

                let size = Int64(rv?.totalFileAllocatedSize ?? rv?.fileSize ?? 0)
                if size < options.minFileSize { continue }

                await emit(
                    FileEntry(
                        url: child,
                        size: size,
                        isSymbolicLink: isSymlink,
                        isPackage: isPackage,
                        modificationDate: rv?.contentModificationDate
                    )
                )
            }
        }
    }
}
