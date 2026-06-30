import XCTest
@testable import NimbusViewModels
import NimbusKit

/// In-memory hasher (groups byte-identical content) so the VM can be tested
/// without the Rust accelerator.
private struct NoopPerceptual: PerceptualHashing {
    func hashBatch(_ paths: [String]) async throws -> PerceptualOutcome { PerceptualOutcome(hashes: []) }
    func groupSimilar(_ hashes: [PerceptualHash], maxDistance: UInt32) async throws -> [[String]] { [] }
}

private struct FNVHasher: ContentHashing {
    func hashBucket(_ paths: [String]) async throws -> ContentHashOutcome {
        var byDigest: [String: [String]] = [:]
        var sizes: [String: Int64] = [:]
        for p in paths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: p)) else { continue }
            var h: UInt64 = 0xcbf29ce484222325
            for b in data { h ^= UInt64(b); h = h &* 0x100000001b3 }
            let d = String(h, radix: 16)
            byDigest[d, default: []].append(p)
            sizes[d] = Int64(data.count)
        }
        let groups = byDigest.filter { $0.value.count > 1 }
            .map { ContentHashGroup(digest: $0.key, fileSize: sizes[$0.key] ?? 0, paths: $0.value.sorted()) }
        return ContentHashOutcome(groups: groups)
    }
}

@MainActor
final class DuplicatesViewModelTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nimbus-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        tmp = tmp.resolvingSymlinksInPath()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func write(_ name: String, _ s: String) throws {
        try s.data(using: .utf8)!.write(to: tmp.appendingPathComponent(name))
    }

    func test_scan_loadsGroupsAndPreselectsAllButOne() async throws {
        try write("a.bin", "same-content-here")
        try write("b.bin", "same-content-here")
        try write("c.bin", "same-content-here")
        try write("u.bin", "unique")

        let vm = DuplicatesViewModel(hasher: FNVHasher(), perceptualHasher: NoopPerceptual(), roots: [tmp], minFileSize: 1)
        await vm.performScan()

        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups[0].files.count, 3)
        // Smart default keeps one, selects the other two.
        XCTAssertEqual(vm.selection.count, 2)
        XCTAssertGreaterThan(vm.reclaimableSelected, 0)
    }

    func test_emptyResult_whenNoDuplicates() async throws {
        try write("a.bin", "one")
        try write("b.bin", "two")
        let vm = DuplicatesViewModel(hasher: FNVHasher(), perceptualHasher: NoopPerceptual(), roots: [tmp], minFileSize: 1)
        await vm.performScan()
        XCTAssertTrue(vm.groups.isEmpty)
        XCTAssertEqual(vm.selection.count, 0)
    }
}
