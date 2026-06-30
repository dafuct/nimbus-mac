import Foundation
import NimbusKit
import CoreGraphics
import ImageIO

// NOTE: This file is compiled by the *Xcode* app target, alongside the
// UniFFI-generated `nimbus_core.swift` (see Sources/NimbusFFI/generated/) and the
// `nimbus_coreFFI` C module map. It is intentionally NOT part of Package.swift —
// SPM doesn't build the Rust static library, so NimbusKit stays Rust-free and
// these adapters live where the linked binary exists. See docs/FFI.md.
//
// The free functions `hashFiles`, `dhashFiles`, `dhashLuma8`, `groupSimilar`
// and the record types `PhashItem` etc. are provided by the generated module.

/// Adapts the Rust `hash_files` export to NimbusKit's `ContentHashing` protocol.
public struct RustContentHasher: ContentHashing {
    public init() {}

    public func hashBucket(_ paths: [String]) async throws -> ContentHashOutcome {
        // Hop off the main actor; the Rust call is synchronous + CPU-heavy.
        await Task.detached(priority: .userInitiated) {
            let outcome = hashFiles(paths: paths)
            let groups = outcome.groups.map {
                ContentHashGroup(digest: $0.digest, fileSize: Int64($0.fileSize), paths: $0.paths)
            }
            let failures = outcome.errors.map { HashFailure(path: $0.path, message: $0.message) }
            return ContentHashOutcome(groups: groups, failures: failures)
        }.value
    }
}

/// Adapts the Rust perceptual-hash exports. Formats the `image` crate can't
/// decode (HEIC/RAW) come back as errors from `dhashFiles`; we transparently
/// decode those via ImageIO and route them through `dhashLuma8`.
public struct RustPerceptualHasher: PerceptualHashing {
    public init() {}

    public func hashBatch(_ paths: [String]) async throws -> PerceptualOutcome {
        await Task.detached(priority: .userInitiated) {
            let outcome = dhashFiles(paths: paths)
            var hashes = outcome.items.map { PerceptualHash(path: $0.path, hash: $0.hash) }
            var failures: [HashFailure] = []
            for err in outcome.errors {
                if let h = Self.lumaHash(path: err.path) {
                    hashes.append(PerceptualHash(path: err.path, hash: h))
                } else {
                    failures.append(HashFailure(path: err.path, message: err.message))
                }
            }
            return PerceptualOutcome(hashes: hashes, failures: failures)
        }.value
    }

    public func groupSimilar(_ hashes: [PerceptualHash], maxDistance: UInt32) async throws -> [[String]] {
        await Task.detached(priority: .userInitiated) {
            // `PhashItem` is the UniFFI record. Module-qualify the call so it
            // resolves to the generated free function, not this protocol method.
            let items = hashes.map { PhashItem(path: $0.path, hash: $0.hash) }
            return Nimbus.groupSimilar(items: items, maxDistance: maxDistance).map { $0.paths }
        }.value
    }

    /// Decode any image ImageIO understands into a small grayscale buffer and
    /// hand it to the Rust dHash. macOS ships native HEIC/RAW decoders here.
    static func lumaHash(path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        let width = 32, height = 32
        var buffer = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &buffer,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return dhashLuma8(width: UInt32(width), height: UInt32(height), luma: Data(buffer))
    }
}
