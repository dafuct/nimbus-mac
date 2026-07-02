import XCTest
@testable import NimbusKit

final class LeftoverResolverTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nimbus-leftovers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        tmp = tmp.resolvingSymlinksInPath()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeDir(_ relative: String, file: String? = nil) throws -> URL {
        let dir = tmp.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let file {
            try "data".data(using: .utf8)!.write(to: dir.appendingPathComponent(file))
        }
        return dir
    }

    func test_resolve_findsDarwinUserCacheAndTempDirs() async throws {
        // Fake ~/Library plus the per-user /var/folders C (cache) and T (temp) dirs.
        let library = try makeDir("Library")
        let libCaches = try makeDir("Library/Caches/com.example.app", file: "f.bin")
        let darwinCache = try makeDir("C")
        let darwinTemp = try makeDir("T")
        let cacheLeftover = try makeDir("C/com.example.app", file: "c.bin")
        let tempLeftover = try makeDir("T/com.example.app", file: "t.bin")
        let bundle = try makeDir("Example.app", file: "Info.plist")

        let app = InstalledApp(bundleID: "com.example.app", name: "Example", url: bundle, version: "1.0")
        let resolver = LeftoverResolver(library: library, darwinCacheDir: darwinCache, darwinTempDir: darwinTemp)
        let leftovers = await resolver.resolve(for: app)

        let byURL = Dictionary(uniqueKeysWithValues: leftovers.map { ($0.url.path, $0.kind) })
        XCTAssertEqual(byURL[bundle.path], .appBundle)
        XCTAssertEqual(byURL[libCaches.path], .caches)
        XCTAssertEqual(byURL[cacheLeftover.path], .caches, "per-user DARWIN_USER_CACHE_DIR leftover must be found")
        XCTAssertEqual(byURL[tempLeftover.path], .temp, "per-user DARWIN_USER_TEMP_DIR leftover must be found")
        // Every found leftover carries its on-disk size.
        for leftover in leftovers where leftover.url != bundle {
            XCTAssertGreaterThan(leftover.bytes, 0, "\(leftover.url.path) should be sized")
        }
    }

    func test_resolve_skipsAbsentDarwinDirsWithoutFailing() async throws {
        let library = try makeDir("Library")
        let bundle = try makeDir("Example.app", file: "Info.plist")
        let app = InstalledApp(bundleID: "com.example.app", name: "Example", url: bundle, version: "1.0")

        // No C/T dirs at all (nil) — resolver must still return the bundle.
        let resolver = LeftoverResolver(library: library, darwinCacheDir: nil, darwinTempDir: nil)
        let leftovers = await resolver.resolve(for: app)
        XCTAssertEqual(leftovers.map(\.url), [bundle])
    }

    func test_defaultInit_probesRealDarwinUserDirs() {
        // The production initializer must resolve both confstr dirs on macOS.
        let cache = LeftoverResolver.darwinUserDir(_CS_DARWIN_USER_CACHE_DIR)
        let temp = LeftoverResolver.darwinUserDir(_CS_DARWIN_USER_TEMP_DIR)
        XCTAssertNotNil(cache)
        XCTAssertNotNil(temp)
        XCTAssertTrue(cache!.path.contains("/folders/"), "expected /private/var/folders path, got \(cache!.path)")
        XCTAssertTrue(temp!.path.contains("/folders/"), "expected /private/var/folders path, got \(temp!.path)")
    }
}
