import Foundation

/// Finds perceptually-similar photos. Same shape as `DuplicateScanner` but the
/// clustering is global (similarity crosses size boundaries), so Swift collects
/// all hashes (in cancellable batches) and Rust clusters them in one pass.
public struct SimilarPhotoScanner: Sendable {
    private let hasher: PerceptualHashing

    /// Extensions worth perceptually hashing. HEIC/RAW are included; the Rust
    /// hasher routes formats it can't decode through ImageIO on the Swift side.
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp",
        "heic", "heif", "raw", "cr2", "nef", "arw", "dng",
    ]

    public init(hasher: PerceptualHashing) {
        self.hasher = hasher
    }

    public func findSimilar(
        roots: [URL],
        maxDistance: UInt32 = 10,
        batchSize: Int = 256,
        exclusions: ExclusionMatcher = .empty,
        onProgress: ProgressHandler? = nil
    ) async throws -> [SimilarPhotoGroup] {
        var options = ScanOptions()
        options.skipPackages = true
        options.exclusions = exclusions
        options.minFileSize = 1

        // 1: collect image candidates + remember sizes.
        var sizeByPath: [String: Int64] = [:]
        var progress = ScanProgress.zero
        for root in roots {
            for try await entry in FileSystemScanner.entries(root: root, options: options) {
                let ext = entry.url.pathExtension.lowercased()
                guard Self.imageExtensions.contains(ext) else { continue }
                sizeByPath[entry.url.path] = entry.size
                progress.filesSeen += 1
                progress.bytesSeen += entry.size
                progress.currentPath = entry.url.path
                if progress.filesSeen % 128 == 0 { onProgress?(progress) }
            }
        }
        onProgress?(progress)

        // 2: hash in cancellable batches (CPU-bound, in Rust).
        let paths = Array(sizeByPath.keys)
        var hashes: [PerceptualHash] = []
        var index = 0
        while index < paths.count {
            try Task.checkCancellation()
            let batch = Array(paths[index ..< min(index + batchSize, paths.count)])
            let outcome = try await hasher.hashBatch(batch)
            hashes.append(contentsOf: outcome.hashes)
            index += batch.count
        }

        // 3: one global clustering pass.
        try Task.checkCancellation()
        let clusters = try await hasher.groupSimilar(hashes, maxDistance: maxDistance)

        // 4: build domain groups.
        var groups: [SimilarPhotoGroup] = clusters.compactMap { cluster in
            guard cluster.count > 1 else { return nil }
            let photos = cluster.map { path in
                SimilarPhoto(url: URL(fileURLWithPath: path), size: sizeByPath[path] ?? 0)
            }
            return SimilarPhotoGroup(id: cluster.sorted().first ?? UUID().uuidString, photos: photos)
        }
        groups.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return groups
    }
}
