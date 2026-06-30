import XCTest
@testable import NimbusKit

final class CleanupScannerTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nimbus-cleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        tmp = tmp.resolvingSymlinksInPath()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func test_scan_includesOnlyRuleApprovedItemsAndSizesThem() async throws {
        // base/cacheA (auto), base/cacheB (auto), base/keepme (no rule -> excluded)
        let cacheA = tmp.appendingPathComponent("cacheA")
        try FileManager.default.createDirectory(at: cacheA, withIntermediateDirectories: true)
        try "1234567890".data(using: .utf8)!.write(to: cacheA.appendingPathComponent("f.bin"))
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("keepme"), withIntermediateDirectories: true)

        let rule = SafetyRule(
            id: "test.cache",
            category: .userCaches,
            disposition: .autoSelectable,
            reason: "test",
            matcher: PathMatcher(globs: ["\(tmp.path)/cache*"])
        )
        let engine = SafetyRuleEngine(rules: [rule], osVersion: .tahoe)
        let scanner = CleanupScanner(engine: engine)

        let groups = try await scanner.scan(bases: [tmp])
        XCTAssertEqual(groups.count, 1)
        let items = groups[0].items
        XCTAssertEqual(items.count, 1, "only cacheA matches and exists with content")
        XCTAssertEqual(items[0].url.lastPathComponent, "cacheA")
        // On-disk allocated size (>= logical 10 bytes; one APFS block in practice).
        XCTAssertGreaterThanOrEqual(items[0].bytes, 10)
        XCTAssertTrue(items[0].autoSelected)
    }
}

final class DefaultExclusionsTests: XCTestCase {
    func test_spaceLensDefaults_skipHeavyAndCloudButKeepRealFiles() {
        let m = DefaultExclusions.spaceLens()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(m.shouldExclude(path: "\(home)/Library/CloudStorage/OneDrive/big.bin"))
        XCTAssertTrue(m.shouldExclude(path: "\(home)/Library/Caches/com.example.app"))
        XCTAssertTrue(m.shouldExclude(path: "\(home)/dev/proj/node_modules"))
        XCTAssertTrue(m.shouldExclude(path: "\(home)/dev/proj/.build"))
        XCTAssertFalse(m.shouldExclude(path: "\(home)/dev/proj/Sources/main.swift"))
        XCTAssertFalse(m.shouldExclude(path: "\(home)/Documents/report.pdf"))
    }
}

final class HealthMonitorTests: XCTestCase {
    func test_memorySnapshot_returnsPlausibleValues() {
        let snapshot = MemoryStatisticsReader().snapshot()
        XCTAssertGreaterThan(snapshot.total, 0)
        XCTAssertGreaterThanOrEqual(snapshot.free, 0)
        XCTAssertLessThanOrEqual(snapshot.used, snapshot.total)
        XCTAssertTrue((0.0...1.0).contains(snapshot.usedFraction))
    }
}
