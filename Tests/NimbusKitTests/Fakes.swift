import Foundation
@testable import NimbusKit

/// Deterministic in-memory content hasher: reads bytes, groups identical content
/// via FNV-1a. Lets `DuplicateScanner` be tested without the Rust accelerator.
struct FakeContentHasher: ContentHashing {
    func hashBucket(_ paths: [String]) async throws -> ContentHashOutcome {
        var byDigest: [String: [String]] = [:]
        var sizeByDigest: [String: Int64] = [:]
        var failures: [HashFailure] = []
        for path in paths {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let digest = Self.fnv1a(data)
                byDigest[digest, default: []].append(path)
                sizeByDigest[digest] = Int64(data.count)
            } catch {
                failures.append(HashFailure(path: path, message: "\(error)"))
            }
        }
        let groups = byDigest
            .filter { $0.value.count > 1 }
            .map { ContentHashGroup(digest: $0.key, fileSize: sizeByDigest[$0.key] ?? 0, paths: $0.value.sorted()) }
        return ContentHashOutcome(groups: groups, failures: failures)
    }

    static func fnv1a(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}

/// Perceptual hasher driven by a preset filename→hash table (keyed by last path
/// component so it's immune to /var↔/private/var canonicalization); clusters with
/// a small in-test Hamming union-find so `SimilarPhotoScanner` plumbing can be
/// verified.
struct FakePerceptualHasher: PerceptualHashing {
    /// Keyed by file name (e.g. "x.jpg").
    var table: [String: UInt64]

    func hashBatch(_ paths: [String]) async throws -> PerceptualOutcome {
        let hashes = paths.compactMap { path -> PerceptualHash? in
            let name = URL(fileURLWithPath: path).lastPathComponent
            return table[name].map { PerceptualHash(path: path, hash: $0) }
        }
        return PerceptualOutcome(hashes: hashes)
    }

    func groupSimilar(_ hashes: [PerceptualHash], maxDistance: UInt32) async throws -> [[String]] {
        var parent = Array(0 ..< hashes.count)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            return r
        }
        func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }
        for i in 0 ..< hashes.count {
            for j in (i + 1) ..< hashes.count {
                let d = (hashes[i].hash ^ hashes[j].hash).nonzeroBitCount
                if d <= Int(maxDistance) { union(i, j) }
            }
        }
        var clusters: [Int: [String]] = [:]
        for i in 0 ..< hashes.count {
            clusters[find(i), default: []].append(hashes[i].path)
        }
        return clusters.values.map { $0.sorted() }
    }
}
