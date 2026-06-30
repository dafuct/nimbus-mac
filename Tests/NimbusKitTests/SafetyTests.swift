import XCTest
@testable import NimbusKit

final class SafetyRuleTests: XCTestCase {
    private func rule(min: OSVersion? = nil, max: OSVersion? = nil, app: String? = nil) -> SafetyRule {
        SafetyRule(
            id: "t", category: .userCaches, disposition: .autoSelectable, reason: "",
            matcher: PathMatcher(globs: ["/x/*"]), minOS: min, maxOS: max, requiresApp: app
        )
    }

    func test_osGating() {
        let r = rule(min: .tahoe)
        XCTAssertFalse(r.isActive(on: .sequoia, installedApps: []))
        XCTAssertTrue(r.isActive(on: .tahoe, installedApps: []))
    }

    func test_maxOSGating() {
        let r = rule(max: OSVersion(15, .max, .max))
        XCTAssertTrue(r.isActive(on: .sequoia, installedApps: []))
        XCTAssertFalse(r.isActive(on: .tahoe, installedApps: []))
    }

    func test_appGating() {
        let r = rule(app: "com.apple.dt.Xcode")
        XCTAssertFalse(r.isActive(on: .tahoe, installedApps: []))
        XCTAssertTrue(r.isActive(on: .tahoe, installedApps: ["com.apple.dt.Xcode"]))
    }
}

final class SafetyRuleEngineTests: XCTestCase {
    let home = FileManager.default.homeDirectoryForCurrentUser

    private func engine(exclusions: ExclusionMatcher = .empty, apps: Set<String> = []) -> SafetyRuleEngine {
        SafetyRuleEngine(
            rules: SafetyCatalog.standard(),
            exclusions: exclusions,
            osVersion: .tahoe,
            installedApps: apps
        )
    }

    func test_userCaches_areAutoSelectable() {
        let url = home.appendingPathComponent("Library/Caches/com.example.App")
        let d = engine().evaluate(url)
        XCTAssertEqual(d.disposition, .autoSelectable)
        XCTAssertEqual(d.category, .userCaches)
    }

    func test_unknownPath_isProtectedByDefault() {
        let url = home.appendingPathComponent("Documents/thesis.txt")
        let d = engine().evaluate(url)
        XCTAssertEqual(d.disposition, .protected)
        XCTAssertEqual(d.ruleID, "default.deny")
    }

    func test_exclusion_overridesEverything() {
        let url = home.appendingPathComponent("Library/Caches/com.example.App")
        let excl = ExclusionMatcher(literals: [url.path])
        let d = engine(exclusions: excl).evaluate(url)
        XCTAssertEqual(d.disposition, .protected)
        XCTAssertEqual(d.ruleID, "user.exclusion")
    }

    func test_stricterDispositionWins() {
        // Matches both user.caches (auto) and user.caches.cloudkit (manual).
        let url = home.appendingPathComponent("Library/Caches/CloudKit")
        let d = engine().evaluate(url)
        XCTAssertEqual(d.disposition, .selectableManually)
        XCTAssertEqual(d.ruleID, "user.caches.cloudkit")
    }

    func test_appGatedRule_inactiveWithoutApp() {
        let url = home.appendingPathComponent("Library/Developer/Xcode/DerivedData/MyApp-abc")
        // No Xcode -> derived-data rule inactive -> falls through to default deny.
        XCTAssertEqual(engine().evaluate(url).disposition, .protected)
        // With Xcode installed -> auto-selectable.
        let d = engine(apps: ["com.apple.dt.Xcode"]).evaluate(url)
        XCTAssertEqual(d.disposition, .autoSelectable)
        XCTAssertEqual(d.ruleID, "xcode.derivedData")
    }

    func test_iosBackups_areProtected() {
        let url = home.appendingPathComponent("Library/Application Support/MobileSync/Backup/UDID")
        XCTAssertEqual(engine().evaluate(url).disposition, .protected)
    }
}

final class SafetyCatalogIOTests: XCTestCase {
    func test_standardCatalogRoundTripsThroughJSON() throws {
        let doc = SafetyCatalog.document(from: SafetyCatalog.standard())
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(SafetyCatalogDocument.self, from: data)
        XCTAssertEqual(decoded.rules.count, SafetyCatalog.standard().count)
        XCTAssertTrue(decoded.rules.contains { $0.id == "user.caches" && $0.disposition == "autoSelectable" })
    }

    func test_engineUsesRulesLoadedFromJSON() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nimbus-cat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let doc = SafetyCatalogDocument(rules: [
            SafetyRuleDTO(id: "custom.tmp", category: "Logs", disposition: "autoSelectable",
                          reason: "test", globs: ["/tmp/nimbustest/*"], minOS: nil, maxOS: nil, requiresApp: nil)
        ])
        let url = dir.appendingPathComponent("catalog.json")
        try JSONEncoder().encode(doc).write(to: url)

        let rules = try SafetyCatalog.load(from: url)
        XCTAssertEqual(rules.count, 1)
        let engine = SafetyRuleEngine(rules: rules, osVersion: .tahoe)
        let decision = engine.evaluate(URL(fileURLWithPath: "/tmp/nimbustest/log1"))
        XCTAssertEqual(decision.disposition, .autoSelectable)
        XCTAssertEqual(decision.ruleID, "custom.tmp")
    }
}

final class RemoverTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nimbus-remover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        tmp = tmp.resolvingSymlinksInPath()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeFile(_ name: String) throws -> RemovalItem {
        let url = tmp.appendingPathComponent(name)
        try "data".data(using: .utf8)!.write(to: url)
        return RemovalItem(url: url, bytes: 4)
    }

    func test_dryRun_changesNothing() async throws {
        let item = try makeFile("a.txt")
        let report = await Remover(dryRun: true).remove([item])
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertEqual(report.projectedBytes, 4)
        XCTAssertEqual(report.reclaimedBytes, 0)
    }

    func test_permanentDelete_requiresExplicitConfirmation() async throws {
        let item = try makeFile("b.txt")
        let refused = await Remover().remove([item], mode: .permanentDelete, allowPermanent: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertEqual(refused.refused.count, 1)

        let confirmed = await Remover().remove([item], mode: .permanentDelete, allowPermanent: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.url.path))
        XCTAssertEqual(confirmed.reclaimedBytes, 4)
    }

    func test_criticalPaths_areRefusedEvenWhenConfirmed() async throws {
        let critical = [
            RemovalItem(url: URL(fileURLWithPath: "/System"), bytes: 0),
            RemovalItem(url: URL(fileURLWithPath: "/"), bytes: 0),
            RemovalItem(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"), bytes: 0),
        ]
        let report = await Remover().remove(critical, mode: .permanentDelete, allowPermanent: true)
        XCTAssertEqual(report.refused.count, 3)
    }

    func test_criticalGuard_allowsUsrLocalException() {
        let guardian = CriticalPathGuard()
        XCTAssertTrue(guardian.isProtected(URL(fileURLWithPath: "/usr/lib")))
        XCTAssertFalse(guardian.isProtected(URL(fileURLWithPath: "/usr/local/bin/tool")))
    }
}
