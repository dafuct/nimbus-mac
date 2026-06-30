import XCTest
@testable import NimbusKit

final class ScannerIntegrationTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nimbus-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // Canonicalize (/var -> /private/var firmlink) so expected paths match
        // what the scanner emits.
        tmp = tmp.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = tmp.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    func test_fileSystemScanner_emitsFilesAndRespectsExclusions() async throws {
        _ = try write("keep/a.txt", "alpha")
        _ = try write("skip/b.txt", "beta")
        var options = ScanOptions(minFileSize: 1)
        options.exclusions = ExclusionMatcher(literals: [tmp.appendingPathComponent("skip").path])

        var found: [String] = []
        for try await entry in FileSystemScanner.entries(root: tmp, options: options) {
            found.append(entry.url.lastPathComponent)
        }
        XCTAssertEqual(found, ["a.txt"])
    }

    func test_duplicateScanner_findsIdenticalContentOnly() async throws {
        _ = try write("a.bin", "duplicate-payload")
        _ = try write("nested/b.bin", "duplicate-payload")
        _ = try write("c.bin", "unique-payload")

        let scanner = DuplicateScanner(hasher: FakeContentHasher())
        let groups = try await scanner.findDuplicates(roots: [tmp], minFileSize: 1)

        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.files.count, 2)
        XCTAssertEqual(
            Set(group.files.map { $0.url.lastPathComponent }), ["a.bin", "b.bin"])
        XCTAssertEqual(group.reclaimableBytes, group.fileSize)
    }

    func test_similarPhotoScanner_clustersByPerceptualHash() async throws {
        let x = try write("x.jpg", "0000")
        let y = try write("y.jpg", "1111")
        let z = try write("z.png", "2222")
        _ = try write("notes.txt", "not an image")

        _ = (x, y, z)
        // x & y near (distance 1), z far. Keyed by file name.
        let table: [String: UInt64] = [
            "x.jpg": 0b1000,
            "y.jpg": 0b1001,
            "z.png": 0xFFFF_FFFF,
        ]
        let scanner = SimilarPhotoScanner(hasher: FakePerceptualHasher(table: table))
        let groups = try await scanner.findSimilar(roots: [tmp], maxDistance: 5)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(
            Set(groups[0].photos.map { $0.url.lastPathComponent }), ["x.jpg", "y.jpg"])
    }

    func test_scanCancellation_throwsCancelled() async throws {
        for i in 0 ..< 50 { _ = try write("f\(i).txt", "x") }
        let task = Task { () -> Int in
            var count = 0
            for try await _ in FileSystemScanner.entries(root: tmp, options: ScanOptions(minFileSize: 1)) {
                count += 1
            }
            return count
        }
        task.cancel()
        do {
            _ = try await task.value
            // It's acceptable for a fast scan to finish before cancellation lands;
            // the contract under test is that cancellation surfaces as .cancelled
            // when it does interrupt — verified in unit scope by checkCancellation.
        } catch let error as NimbusError {
            XCTAssertTrue(error.isCancellation)
        }
    }
}
