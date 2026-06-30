import Foundation

/// Finds byte-identical duplicate files. This is the canonical Swift↔Rust flow:
///
/// 1. **Swift (I/O-bound):** walk roots via the shared `FileSystemScanner` and
///    bucket candidates by exact byte length.
/// 2. **Swift:** discard size buckets with a single file — they can't have a
///    duplicate — so only real candidates reach Rust.
/// 3. **Rust (CPU-bound):** hash each bucket in parallel (BLAKE3 + rayon) and
///    collapse identical content into groups.
/// 4. **Swift:** turn the returned groups into domain models for the UI.
///
/// Per-bucket calls give natural progress + cancellation (Swift owns the loop)
/// while staying correct: identical files necessarily share a size.
public struct DuplicateScanner: Sendable {
    private let hasher: ContentHashing

    public init(hasher: ContentHashing) {
        self.hasher = hasher
    }

    public func findDuplicates(
        roots: [URL],
        minFileSize: Int64 = 4 * 1024,
        exclusions: ExclusionMatcher = .empty,
        onProgress: ProgressHandler? = nil
    ) async throws -> [DuplicateGroup] {
        var options = ScanOptions()
        options.skipPackages = true        // never look inside .app bundles
        options.minFileSize = minFileSize
        options.exclusions = exclusions

        // 1 + 2: collect candidates and bucket by size.
        var bySize: [Int64: [FileEntry]] = [:]
        var progress = ScanProgress.zero
        for root in roots {
            for try await entry in FileSystemScanner.entries(root: root, options: options) {
                bySize[entry.size, default: []].append(entry)
                progress.filesSeen += 1
                progress.bytesSeen += entry.size
                progress.currentPath = entry.url.path
                if progress.filesSeen % 256 == 0 { onProgress?(progress) }
            }
        }
        onProgress?(progress)

        let candidateBuckets = bySize
            .filter { $0.value.count > 1 }
            .sorted { $0.key > $1.key } // hash largest files first — best payoff early

        // 3 + 4: hash each bucket in Rust, build domain groups.
        var groups: [DuplicateGroup] = []
        for (_, bucket) in candidateBuckets {
            try Task.checkCancellation()
            let sizeByPath = Dictionary(uniqueKeysWithValues: bucket.map { ($0.url.path, $0) })
            let outcome = try await hasher.hashBucket(bucket.map { $0.url.path })
            for group in outcome.groups where group.paths.count > 1 {
                let files = group.paths.map { path -> DuplicateFile in
                    let entry = sizeByPath[path]
                    return DuplicateFile(
                        url: URL(fileURLWithPath: path),
                        size: entry?.size ?? group.fileSize,
                        modificationDate: entry?.modificationDate
                    )
                }
                groups.append(
                    DuplicateGroup(digest: group.digest, fileSize: group.fileSize, files: files)
                )
            }
        }

        groups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return groups
    }
}
