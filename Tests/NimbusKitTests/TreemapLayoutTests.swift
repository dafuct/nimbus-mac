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
}
