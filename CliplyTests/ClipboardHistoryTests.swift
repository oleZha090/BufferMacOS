import XCTest
@testable import Cliply

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    func testFirstItemPreservesOriginalText() {
        let history = ClipboardHistoryService()
        history.add("  Hello\nWorld 🌍  ")
        XCTAssertEqual(history.items.compactMap(\.text), ["  Hello\nWorld 🌍  "])
    }

    func testTenItemsAreNewestFirst() {
        let history = ClipboardHistoryService()
        for index in 1...10 { history.add("Text \(index)") }
        XCTAssertEqual(history.items.compactMap(\.text), (1...10).reversed().map { "Text \($0)" })
    }

    func testEleventhEvictsOldestAndCapacityNeverExceeded() {
        let history = ClipboardHistoryService()
        for index in 1...11 { history.add("Text \(index)") }
        XCTAssertEqual(history.items.count, 10)
        XCTAssertEqual(history.items.last?.text, "Text 2")
        for index in 12...200 { history.add("Text \(index)"); XCTAssertLessThanOrEqual(history.items.count, 10) }
        XCTAssertEqual(history.items.first?.text, "Text 200")
    }

    func testDuplicateMovesExistingIdentityToTopAndUpdatesTime() {
        let history = ClipboardHistoryService()
        history.add("one", at: Date(timeIntervalSince1970: 1))
        let originalID = history.items[0].id
        history.add("two")
        let newTime = Date(timeIntervalSince1970: 3)
        history.add("one", at: newTime)
        XCTAssertEqual(history.items.compactMap(\.text), ["one", "two"])
        XCTAssertEqual(history.items[0].id, originalID)
        XCTAssertEqual(history.items[0].copiedAt, newTime)
    }

    func testEmptyAndOversizedTextAreRejectedUsingUTF8Bytes() {
        let history = ClipboardHistoryService()
        ["", " \n\t", String(repeating: "a", count: 102401), String(repeating: "🌍", count: 25601)].forEach { history.add($0) }
        XCTAssertTrue(history.items.isEmpty)
        history.add(String(repeating: "a", count: 102400))
        XCTAssertEqual(history.items.count, 1)
    }

    func testRemoveAndClear() {
        let history = ClipboardHistoryService()
        history.add("a"); history.add("b")
        history.remove(history.items[1].id)
        XCTAssertEqual(history.items.compactMap(\.text), ["b"])
        history.clear()
        XCTAssertTrue(history.items.isEmpty)
    }

    func testSearchIsCaseInsensitiveAndDoesNotMutateHistory() {
        let history = ClipboardHistoryService()
        history.add("Привет Swift"); history.add("Second\nline")
        XCTAssertEqual(history.matching("ПРИВЕТ").compactMap(\.text), ["Привет Swift"])
        XCTAssertEqual(history.matching("LINE").count, 1)
        XCTAssertEqual(history.matching("").count, 2)
        XCTAssertEqual(history.matching("missing").count, 0)
        XCTAssertEqual(history.items.count, 2)
    }

    func testSelectionFollowsFilteredItemsAndAllTenAreReachable() {
        let history = ClipboardHistoryService()
        for index in 1...10 { history.add("Text \(index)") }
        let model = ClipboardViewModel(history: history)
        model.prepareForOpen()
        XCTAssertEqual(model.selectedID, history.items.first?.id)
        for _ in 0..<9 { model.move(1) }
        XCTAssertEqual(model.selectedID, history.items.last?.id)
        model.move(1)
        XCTAssertEqual(model.selectedID, history.items.last?.id)
        model.query = "Text 7"
        XCTAssertEqual(model.selectedID, history.matching("Text 7").first?.id)
        var chosen: ClipboardItem?
        model.onChoose = { chosen = $0 }
        model.choose()
        XCTAssertEqual(chosen?.text, "Text 7")
        model.remove(chosen!)
        XCTAssertNil(model.selectedID)
        model.query = ""
        XCTAssertNotNil(model.selectedID)
        history.clear()
        XCTAssertNil(model.selectedID)
    }
}
