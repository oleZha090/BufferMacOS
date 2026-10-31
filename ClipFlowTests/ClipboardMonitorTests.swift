import AppKit
import XCTest
@testable import ClipFlow

final class MemoryClipboard: ClipboardAccess {
    var changeCount = 0
    var text: String?
    var writeSucceeds = true
    var reads = 0
    var ownWrite = false
    var afterWrite: (() -> Void)?
    func copy(_ text: String?) { self.text = text; changeCount += 1; ownWrite = false }
    func readText() -> String? { reads += 1; return ownWrite ? nil : text }
    func isRestoredTextCurrent(_ text: String) -> Bool { ownWrite && self.text == text }
    func replaceText(_ text: String) -> Bool {
        guard writeSucceeds else { return false }
        copy(text)
        ownWrite = true
        afterWrite?()
        return true
    }
}

final class ClipboardMonitorTests: XCTestCase {
    func testOnlyReadsChangedClipboardAndStartsEmpty() {
        let clipboard = MemoryClipboard()
        clipboard.copy("Existing before launch")
        let tracker = ClipboardTracker(clipboard: clipboard)
        var values: [String] = []
        tracker.onText = { values.append($0) }
        tracker.poll(); tracker.poll()
        XCTAssertEqual(clipboard.reads, 0)
        clipboard.copy("new")
        tracker.poll(); tracker.poll()
        XCTAssertEqual(values, ["new"])
        XCTAssertEqual(clipboard.reads, 1)
    }

    func testUnsupportedEmptyAndOversizedDataIgnored() {
        let clipboard = MemoryClipboard()
        let tracker = ClipboardTracker(clipboard: clipboard)
        var values: [String] = []
        tracker.onText = { values.append($0) }
        for value in [nil, "", " \n", String(repeating: "a", count: 102401)] as [String?] {
            clipboard.copy(value); tracker.poll()
        }
        XCTAssertTrue(values.isEmpty)
    }

    func testRestoreCapturesPendingCopyButNeverAddsItsOwnWrite() {
        let clipboard = MemoryClipboard()
        let tracker = ClipboardTracker(clipboard: clipboard)
        var values: [String] = []
        tracker.onText = { values.append($0) }
        clipboard.copy("external")
        XCTAssertTrue(tracker.restore("selected"))
        tracker.poll()
        XCTAssertEqual(values, ["external"])
        XCTAssertEqual(clipboard.text, "selected")
        clipboard.copy("next external")
        tracker.poll()
        XCTAssertEqual(values, ["external", "next external"])
    }

    func testWriteFailureDoesNotDestroyExistingClipboard() {
        let clipboard = MemoryClipboard()
        clipboard.copy("original")
        let tracker = ClipboardTracker(clipboard: clipboard)
        clipboard.writeSucceeds = false
        XCTAssertFalse(tracker.restore("replacement"))
        XCTAssertEqual(clipboard.text, "original")
    }

    func testExternalCopyRacingWithRestoreIsNotSuppressed() {
        let clipboard = MemoryClipboard()
        let tracker = ClipboardTracker(clipboard: clipboard)
        var values: [String] = []
        tracker.onText = { values.append($0) }
        clipboard.afterWrite = { [weak clipboard] in clipboard?.copy("external during write") }
        XCTAssertTrue(tracker.restore("selected"))
        tracker.poll()
        XCTAssertEqual(values, ["external during write"])
    }

    func testSystemClipboardReadsUTF8AndIgnoresItsOwnRestores() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = SystemClipboard(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("  Привет\n🌍  ", forType: .string)
        XCTAssertEqual(clipboard.readText(), "  Привет\n🌍  ")
        XCTAssertTrue(clipboard.replaceText("selected"))
        XCTAssertNil(clipboard.readText())
        XCTAssertTrue(clipboard.isRestoredTextCurrent("selected"))
        XCTAssertEqual(pasteboard.string(forType: .string), "selected")
    }

    func testSystemClipboardIgnoresConcealedTextAndFileURLs() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = SystemClipboard(pasteboard: pasteboard)
        for type in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "public.file-url"] {
            let item = NSPasteboardItem()
            item.setString("private", forType: .string)
            item.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            pasteboard.clearContents()
            pasteboard.writeObjects([item])
            XCTAssertNil(clipboard.readText())
        }
    }

    func testSystemClipboardAcceptsTextURLAndRejectsOversizedUTF8() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = SystemClipboard(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/path", forType: NSPasteboard.PasteboardType("public.url"))
        XCTAssertEqual(clipboard.readText(), "https://example.com/path")
        pasteboard.clearContents()
        pasteboard.setData(Data(repeating: 97, count: 102401), forType: .string)
        XCTAssertNil(clipboard.readText())
    }
}
