import Foundation

// These protocols are the seam between Swift orchestration and the Rust
// accelerator. NimbusKit depends only on the protocols, so it builds and
// unit-tests with no Rust present; the Xcode app injects a `RustContentHasher` /
// `RustPerceptualHasher` backed by the UniFFI `nimbus_core` bindings (see
// Sources/NimbusFFI), and tests inject in-memory fakes.

public struct ContentHashGroup: Sendable, Hashable {
    public let digest: String
    public let fileSize: Int64
    public let paths: [String]
    public init(digest: String, fileSize: Int64, paths: [String]) {
        self.digest = digest
        self.fileSize = fileSize
        self.paths = paths
    }
}

public struct HashFailure: Sendable, Hashable {
    public let path: String
    public let message: String
    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct ContentHashOutcome: Sendable {
    public let groups: [ContentHashGroup]
    public let failures: [HashFailure]
    public init(groups: [ContentHashGroup], failures: [HashFailure] = []) {
        self.groups = groups
        self.failures = failures
    }
}

/// Parallel byte-identical grouping of a single size bucket. Maps directly onto
/// the Rust `hash_files` export.
public protocol ContentHashing: Sendable {
    func hashBucket(_ paths: [String]) async throws -> ContentHashOutcome
}

public struct PerceptualHash: Sendable, Hashable {
    public let path: String
    public let hash: UInt64
    public init(path: String, hash: UInt64) {
        self.path = path
        self.hash = hash
    }
}

public struct PerceptualOutcome: Sendable {
    public let hashes: [PerceptualHash]
    public let failures: [HashFailure]
    public init(hashes: [PerceptualHash], failures: [HashFailure] = []) {
        self.hashes = hashes
        self.failures = failures
    }
}

/// Perceptual hashing + clustering. Maps onto Rust `dhash_files` /
/// `group_similar` / `dhash_luma8`. The Rust-backed implementation transparently
/// decodes HEIC/RAW via ImageIO and routes them through the luma path.
public protocol PerceptualHashing: Sendable {
    func hashBatch(_ paths: [String]) async throws -> PerceptualOutcome
    func groupSimilar(_ hashes: [PerceptualHash], maxDistance: UInt32) async throws -> [[String]]
}
