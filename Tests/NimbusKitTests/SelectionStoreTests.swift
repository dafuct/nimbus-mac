import XCTest
@testable import NimbusKit

private struct Item: Selectable {
    let id: Int
    let removalBytes: Int64
}

final class SelectionStoreTests: XCTestCase {
    private let items = [
        Item(id: 1, removalBytes: 100),
        Item(id: 2, removalBytes: 200),
        Item(id: 3, removalBytes: 300),
    ]

    func test_toggleAndReclaimable() {
        var store = SelectionStore<Item>()
        store.toggle(2)
        store.toggle(3)
        XCTAssertTrue(store.isSelected(2))
        XCTAssertEqual(store.reclaimableBytes(over: items), 500)
        store.toggle(2)
        XCTAssertEqual(store.reclaimableBytes(over: items), 300)
    }

    func test_selectAllButFirst_keepsOnePerGroup() {
        struct Group { let members: [Item] }
        let groups = [
            Group(members: [Item(id: 1, removalBytes: 100), Item(id: 2, removalBytes: 100), Item(id: 3, removalBytes: 100)]),
            Group(members: [Item(id: 4, removalBytes: 50)]), // singleton: nothing selected
        ]
        var store = SelectionStore<Item>()
        store.selectAllButFirst(in: groups) { $0.members }
        XCTAssertEqual(store.selectedIDs, [2, 3])
    }

    func test_selectAllAndClear() {
        var store = SelectionStore<Item>()
        store.selectAll(items)
        XCTAssertEqual(store.count, 3)
        store.clear()
        XCTAssertTrue(store.isEmpty)
    }
}
