import XCTest
import CoreGraphics
@testable import NimbusKit

final class TreemapLayoutTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    func test_emptyInput_yieldsNoTiles() {
        XCTAssertTrue(TreemapLayout.squarify([(id: 1, weight: 0.0)], in: bounds).isEmpty)
        XCTAssertTrue(TreemapLayout.squarify([(id: 1, weight: 5.0)], in: .zero).isEmpty)
    }

    func test_tileCount_matchesPositiveWeights() {
        let items: [(id: Int, weight: Double)] = [
            (1, 100), (2, 50), (3, 25), (4, 0), (5, -3),
        ]
        let tiles = TreemapLayout.squarify(items, in: bounds)
        XCTAssertEqual(tiles.count, 3, "zero/negative weights are dropped")
    }

    func test_totalArea_approximatesBounds() {
        let items: [(id: Int, weight: Double)] = (1...20).map { ($0, Double($0 * 3 + 1)) }
        let tiles = TreemapLayout.squarify(items, in: bounds)
        let covered = tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        let boundsArea = Double(bounds.width * bounds.height)
        XCTAssertEqual(covered, boundsArea, accuracy: boundsArea * 0.001)
    }

    func test_areaIsProportionalToWeight() {
        let items: [(id: Int, weight: Double)] = [(1, 100), (2, 200)]
        let tiles = TreemapLayout.squarify(items, in: bounds)
        let a1 = tiles.first { $0.id == 1 }!.rect
        let a2 = tiles.first { $0.id == 2 }!.rect
        let area1 = Double(a1.width * a1.height)
        let area2 = Double(a2.width * a2.height)
        XCTAssertEqual(area2 / area1, 2.0, accuracy: 0.01)
    }

    func test_tilesStayWithinBounds() {
        let items: [(id: Int, weight: Double)] = (1...30).map { ($0, Double.random(in: 1...100)) }
        let tiles = TreemapLayout.squarify(items, in: bounds)
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.rect.minX, bounds.minX - 0.001)
            XCTAssertGreaterThanOrEqual(tile.rect.minY, bounds.minY - 0.001)
            XCTAssertLessThanOrEqual(tile.rect.maxX, bounds.maxX + 0.001)
            XCTAssertLessThanOrEqual(tile.rect.maxY, bounds.maxY + 0.001)
            XCTAssertGreaterThan(tile.rect.width, 0)
            XCTAssertGreaterThan(tile.rect.height, 0)
        }
    }

    // MARK: - collapsingTail

    private func node(_ name: String, _ size: Int64, dir: Bool = true) -> DiskUsageNode {
        DiskUsageNode(url: URL(fileURLWithPath: "/x/\(name)"), name: name,
                      isDirectory: dir, size: size, children: [])
    }
    private let otherURL = URL(string: "file:///x#nimbus-other")!

    func test_collapsingTail_foldsSmallChildrenIntoOther() {
        let kids = [node("big", 1_000_000), node("a", 50), node("b", 40), node("c", 30)]
        let out = DiskUsageNode.collapsingTail(kids, boardArea: 1000, minTileArea: 100,
                                               maxTiles: 100, otherURL: otherURL, otherName: "Other")
        XCTAssertEqual(out.map(\.name), ["big", "Other"])
        let other = out.last!
        XCTAssertEqual(other.size, 120)                 // 50 + 40 + 30
        XCTAssertEqual(other.children.count, 3)         // tail kept reachable for drill-in
        XCTAssertTrue(other.isDirectory)
    }

    func test_collapsingTail_keepsAllWhenEveryTileIsLargeEnough() {
        let kids = [node("a", 300), node("b", 300), node("c", 300)]
        let out = DiskUsageNode.collapsingTail(kids, boardArea: 900, minTileArea: 100,
                                               maxTiles: 100, otherURL: otherURL, otherName: "Other")
        XCTAssertEqual(out.map(\.name), ["a", "b", "c"])  // no synthetic tile added
    }

    func test_collapsingTail_alwaysKeepsLargest_soDrillCannotLoop() {
        // Every child is below the floor → keep the biggest, fold the rest, so the
        // set shrinks on drill-in instead of re-wrapping the whole thing forever.
        let kids = (0..<10).map { node("n\($0)", 10) }
        let out = DiskUsageNode.collapsingTail(kids, boardArea: 100, minTileArea: 1000,
                                               maxTiles: 100, otherURL: otherURL, otherName: "Other")
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.last!.children.count, 9)
    }

    func test_collapsingTail_singleTailItemIsNotWrapped() {
        let kids = [node("big", 1000), node("solo", 1)]
        let out = DiskUsageNode.collapsingTail(kids, boardArea: 1000, minTileArea: 100,
                                               maxTiles: 100, otherURL: otherURL, otherName: "Other")
        XCTAssertEqual(out.map(\.name), ["big", "solo"])  // wrapping one item helps nothing
    }

    func test_collapsingTail_capsTileCount_evenWhenAllClearTheAreaFloor() {
        // 40 equally-large tiles all clear the area floor, but the count cap must
        // still fold everything past the cap into one "Other" so the board can't
        // fan out into dozens of thin slivers.
        let kids = (0..<40).map { node("n\($0)", 1_000_000) }
        let out = DiskUsageNode.collapsingTail(kids, boardArea: 1_000_000, minTileArea: 1,
                                               maxTiles: 18, otherURL: otherURL, otherName: "Other")
        XCTAssertEqual(out.count, 18)                      // 17 real + 1 "Other"
        XCTAssertEqual(out.last!.name, "Other")
        XCTAssertEqual(out.last!.children.count, 40 - 17)  // remainder folded in
    }
}
