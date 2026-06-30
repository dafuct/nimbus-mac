import XCTest
@testable import NimbusKit

final class DiskUsageTreeBuilderTests: XCTestCase {
    let root = URL(fileURLWithPath: "/Users/x/Project")

    private func entry(_ path: String, _ size: Int64) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: path), size: size)
    }

    func test_aggregatesSizesUpTheTree() {
        let entries = [
            entry("/Users/x/Project/a.txt", 100),
            entry("/Users/x/Project/sub/b.txt", 200),
            entry("/Users/x/Project/sub/c.txt", 300),
        ]
        let tree = DiskUsageTreeBuilder.build(root: root, entries: entries)

        XCTAssertEqual(tree.size, 600)
        XCTAssertEqual(tree.name, "Project")
        let sub = tree.children.first { $0.name == "sub" }
        XCTAssertNotNil(sub)
        XCTAssertEqual(sub?.size, 500)
        XCTAssertTrue(sub?.isDirectory ?? false)
        XCTAssertEqual(sub?.children.count, 2)
    }

    func test_childrenSortedBySizeDescending() {
        let entries = [
            entry("/Users/x/Project/small.txt", 10),
            entry("/Users/x/Project/big.txt", 1000),
            entry("/Users/x/Project/mid.txt", 100),
        ]
        let tree = DiskUsageTreeBuilder.build(root: root, entries: entries)
        XCTAssertEqual(tree.children.map(\.name), ["big.txt", "mid.txt", "small.txt"])
    }

    func test_ignoresEntriesOutsideRoot() {
        let entries = [
            entry("/Users/x/Project/in.txt", 50),
            entry("/Users/x/Other/out.txt", 9999),
        ]
        let tree = DiskUsageTreeBuilder.build(root: root, entries: entries)
        XCTAssertEqual(tree.size, 50)
        XCTAssertEqual(tree.children.count, 1)
    }
}
