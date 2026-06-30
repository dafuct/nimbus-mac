import Foundation
import CoreGraphics

/// One laid-out rectangle in a treemap.
public struct TreemapTile<ID: Hashable>: Hashable {
    public let id: ID
    public let rect: CGRect
    public init(id: ID, rect: CGRect) {
        self.id = id
        self.rect = rect
    }
}

/// Pure squarified-treemap layout (Bruls, Huizing & van Wijk). Given weighted
/// items and a bounding rect, returns non-overlapping tiles whose areas are
/// proportional to weight, favoring near-square aspect ratios.
///
/// Pure and deterministic — hence unit-testable without any UI.
public enum TreemapLayout {

    public static func squarify<ID: Hashable>(
        _ items: [(id: ID, weight: Double)],
        in bounds: CGRect
    ) -> [TreemapTile<ID>] {
        let positive = items.filter { $0.weight > 0 }
        guard !positive.isEmpty, bounds.width > 0, bounds.height > 0 else { return [] }

        let totalWeight = positive.reduce(0) { $0 + $1.weight }
        let scale = (Double(bounds.width) * Double(bounds.height)) / totalWeight
        // Largest first is what makes squarify produce tidy tiles.
        let sorted = positive
            .map { (id: $0.id, area: $0.weight * scale) }
            .sorted { $0.area > $1.area }

        var tiles: [TreemapTile<ID>] = []
        var free = bounds
        var row: [(id: ID, area: Double)] = []
        var index = 0

        while index < sorted.count {
            let side = Double(min(free.width, free.height))
            let candidate = sorted[index]
            let currentAreas = row.map(\.area)

            if row.isEmpty || worst(currentAreas, side) >= worst(currentAreas + [candidate.area], side) {
                row.append(candidate)
                index += 1
            } else {
                let (placed, remaining) = layoutRow(row, in: free)
                tiles.append(contentsOf: placed)
                free = remaining
                row.removeAll(keepingCapacity: true)
            }
        }
        if !row.isEmpty {
            let (placed, _) = layoutRow(row, in: free)
            tiles.append(contentsOf: placed)
        }
        return tiles
    }

    /// Worst (largest) aspect ratio in a row laid along a side of length `side`.
    private static func worst(_ areas: [Double], _ side: Double) -> Double {
        guard let maxA = areas.max(), let minA = areas.min(), minA > 0, side > 0 else {
            return .greatestFiniteMagnitude
        }
        let sum = areas.reduce(0, +)
        let side2 = side * side
        let sum2 = sum * sum
        return Swift.max(side2 * maxA / sum2, sum2 / (side2 * minA))
    }

    private static func layoutRow<ID: Hashable>(
        _ row: [(id: ID, area: Double)],
        in free: CGRect
    ) -> (tiles: [TreemapTile<ID>], remaining: CGRect) {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0 else { return ([], free) }
        var tiles: [TreemapTile<ID>] = []

        if free.width >= free.height {
            // Lay a column on the left; column width = area / column height.
            let columnWidth = CGFloat(sum) / free.height
            var y = free.minY
            for member in row {
                let h = CGFloat(member.area) / columnWidth
                tiles.append(TreemapTile(id: member.id, rect: CGRect(x: free.minX, y: y, width: columnWidth, height: h)))
                y += h
            }
            let remaining = CGRect(
                x: free.minX + columnWidth,
                y: free.minY,
                width: free.width - columnWidth,
                height: free.height
            )
            return (tiles, remaining)
        } else {
            // Lay a row across the top; row height = area / row width.
            let rowHeight = CGFloat(sum) / free.width
            var x = free.minX
            for member in row {
                let w = CGFloat(member.area) / rowHeight
                tiles.append(TreemapTile(id: member.id, rect: CGRect(x: x, y: free.minY, width: w, height: rowHeight)))
                x += w
            }
            let remaining = CGRect(
                x: free.minX,
                y: free.minY + rowHeight,
                width: free.width,
                height: free.height - rowHeight
            )
            return (tiles, remaining)
        }
    }
}
