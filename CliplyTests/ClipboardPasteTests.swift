import XCTest
@testable import Cliply

@MainActor
final class TestPasteTarget: PasteTarget {
    let processIdentifier: Int32 = 42
    var isTerminated = false
}

@MainActor
final class TestClipboardWriter: ClipboardWriting {
    var contents: [ClipboardContent] = []
    var texts: [String] { contents.compactMap(\.text) }
    var succeeds = true
    var yields = false
    var current = true
    func restore(_ content: ClipboardContent) async -> Bool {
        contents.append(content)
        if yields { await Task.yield() }
        return succeeds
    }
    func isRestoredContentCurrent(_ content: ClipboardContent) async -> Bool { current && contents.last == content }
}

@MainActor
final class TestPasteEnvironment: PasteEnvironment {
    var canPostEvents = true
    var frontmostPID: Int32? = 99
    var modifiersReleased = true
    var activationSucceeds = true
    var focusSucceeds = true
    var postsSucceed = true
    var activateAtCheck: Int? = 2
    var waits = 0
    var activations = 0
    var posted: [Int32] = []
    var beforePost: (() -> Void)?
    var onRestoreFocus: (() -> Void)?
    func activate(_ target: PasteTarget) -> Bool { activations += 1; return activationSucceeds }
    func restoreFocus(_ target: PasteTarget) -> Bool { onRestoreFocus?(); return focusSucceeds }
    func postPaste(to target: PasteTarget) -> Bool {
        beforePost?()
        guard postsSucceed, canPostEvents, frontmostPID == target.processIdentifier else { return false }
        posted.append(target.processIdentifier)
        return true
    }
    func waitForNextCheck() async {
        waits += 1
        if waits == activateAtCheck { frontmostPID = 42 }
        await Task.yield()
    }
}

@MainActor
final class ClipboardPasteTests: XCTestCase {
    func testImageSelectionClosesPanelAndPostsOnceToOriginalApp() async throws {
        let writer = TestClipboardWriter()
        let environment = TestPasteEnvironment()
        let service = ClipboardPasteService(clipboard: writer, environment: environment)
        let content = ClipboardContent.image(try ClipboardImageFixture.image())
        var closes = 0
        let result = await service.paste(content, to: TestPasteTarget()) { closes += 1 }
        XCTAssertEqual(result, .posted)
        XCTAssertEqual(writer.contents, [content])
        XCTAssertTrue(writer.texts.isEmpty)
        XCTAssertEqual(environment.posted, [42])
        XCTAssertEqual(closes, 1)
    }

    func testImageWithoutPermissionIsKeptForManualPaste() async throws {
        let writer = TestClipboardWriter()
        let environment = TestPasteEnvironment()
        environment.canPostEvents = false
        let service = ClipboardPasteService(clipboard: writer, environment: environment)
        let content = ClipboardContent.image(try ClipboardImageFixture.image())
        var closed = false
        let result = await service.paste(content, to: TestPasteTarget()) { closed = true }
        guard case .manual = result else { return XCTFail("Expected manual image paste") }
        XCTAssertEqual(writer.contents, [content])
        XCTAssertTrue(closed)
        XCTAssertTrue(environment.posted.isEmpty)
    }

    func testWaitsForOriginalAppThenPostsExactlyOnceAfterClosingPanel() async {
        let writer = TestClipboardWriter()
        let environment = TestPasteEnvironment()
        let service = ClipboardPasteService(clipboard: writer, environment: environment)
        var closed = false
        environment.beforePost = { XCTAssertTrue(closed) }
        let result = await service.paste("a\nb", to: TestPasteTarget()) { closed = true }
        XCTAssertEqual(result, .posted)
        XCTAssertEqual(writer.texts, ["a\nb"])
        XCTAssertEqual(environment.posted, [42])
        XCTAssertGreaterThanOrEqual(environment.waits, 3)
    }

    func testNoPermissionCopiesClosesAndReturnsToTargetWithoutPosting() async {
        let writer = TestClipboardWriter()
        let environment = TestPasteEnvironment()
        environment.canPostEvents = false
        let service = ClipboardPasteService(clipboard: writer, environment: environment)
        var closed = false
        let result = await service.paste("manual", to: TestPasteTarget()) { closed = true }
        guard case .manual = result else { return XCTFail("Expected manual fallback") }
        XCTAssertEqual(writer.texts, ["manual"])
        XCTAssertTrue(closed)
        XCTAssertEqual(environment.activations, 1)
        XCTAssertTrue(environment.posted.isEmpty)
    }

    func testWrongForegroundAppTimesOutWithoutPosting() async {
        let environment = TestPasteEnvironment()
        environment.activateAtCheck = nil
        let service = ClipboardPasteService(clipboard: TestClipboardWriter(), environment: environment)
        let result = await service.paste("safe", to: TestPasteTarget()) {}
        guard case .manual = result else { return XCTFail("Expected fallback") }
        XCTAssertTrue(environment.posted.isEmpty)
        XCTAssertLessThanOrEqual(environment.waits, 50)
    }

    func testFocusChangesDuringRestorationCannotPasteIntoAnotherApp() async {
        let environment = TestPasteEnvironment()
        environment.onRestoreFocus = { environment.frontmostPID = 100 }
        let service = ClipboardPasteService(clipboard: TestClipboardWriter(), environment: environment)
        let result = await service.paste("safe", to: TestPasteTarget()) {}
        guard case .manual = result else { return XCTFail("Expected fallback") }
        XCTAssertTrue(environment.posted.isEmpty)
    }

    func testHeldModifiersNeverPost() async {
        let environment = TestPasteEnvironment()
        environment.modifiersReleased = false
        let service = ClipboardPasteService(clipboard: TestClipboardWriter(), environment: environment)
        _ = await service.paste("safe", to: TestPasteTarget()) {}
        XCTAssertTrue(environment.posted.isEmpty)
    }

    func testMissingOrTerminatedTargetStillCopies() async {
        let writer = TestClipboardWriter()
        let environment = TestPasteEnvironment()
        let service = ClipboardPasteService(clipboard: writer, environment: environment)
        _ = await service.paste("no app", to: nil) {}
        let target = TestPasteTarget()
        target.isTerminated = true
        _ = await service.paste("quit app", to: target) {}
        XCTAssertEqual(writer.texts, ["no app", "quit app"])
        XCTAssertEqual(environment.activations, 0)
        XCTAssertTrue(environment.posted.isEmpty)
    }

    func testClipboardFailureKeepsPanelAndNeverActivatesOrPosts() async {
        let writer = TestClipboardWriter()
        writer.succeeds = false
        let environment = TestPasteEnvironment()
        let service = ClipboardPasteService(clipboard: writer, environment: environment)
        var closed = false
        let result = await service.paste("safe", to: TestPasteTarget()) { closed = true }
        XCTAssertEqual(result, .clipboardFailure)
        XCTAssertFalse(closed)
        XCTAssertEqual(environment.activations, 0)
        XCTAssertTrue(environment.posted.isEmpty)
    }

    func testRapidSecondSelectionIsIgnored() async {
        let writer = TestClipboardWriter()
        writer.yields = true
        let environment = TestPasteEnvironment()
        let service = ClipboardPasteService(clipboard: writer, environment: environment)
        let first = Task { await service.paste("first", to: TestPasteTarget()) {} }
        while !service.isPasting { await Task.yield() }
        let second = await service.paste("second", to: TestPasteTarget()) {}
        _ = await first.value
        XCTAssertEqual(second, .ignored)
        XCTAssertEqual(writer.texts, ["first"])
        XCTAssertEqual(environment.posted, [42])
    }

    func testFailedActivationOrFocusUsesManualFallback() async {
        let environment = TestPasteEnvironment()
        let service = ClipboardPasteService(clipboard: TestClipboardWriter(), environment: environment)
        environment.activationSucceeds = false
        let failedActivation = await service.paste("a", to: TestPasteTarget()) {}
        guard case .manual = failedActivation else { return XCTFail("Expected fallback") }
        environment.activationSucceeds = true
        environment.focusSucceeds = false
        let failedFocus = await service.paste("b", to: TestPasteTarget()) {}
        guard case .manual = failedFocus else { return XCTFail("Expected fallback") }
        XCTAssertTrue(environment.posted.isEmpty)
    }

    func testPermissionRevocationAtPostingDoesNotRetry() async {
        let environment = TestPasteEnvironment()
        environment.beforePost = { environment.canPostEvents = false }
        let service = ClipboardPasteService(clipboard: TestClipboardWriter(), environment: environment)
        let result = await service.paste("safe", to: TestPasteTarget()) {}
        guard case .manual = result else { return XCTFail("Expected manual fallback") }
        XCTAssertTrue(environment.posted.isEmpty)
    }

    func testClipboardChangedDuringActivationIsPreservedWithoutPosting() async {
        let writer = TestClipboardWriter()
        writer.current = false
        let environment = TestPasteEnvironment()
        let service = ClipboardPasteService(clipboard: writer, environment: environment)
        let result = await service.paste("selected", to: TestPasteTarget()) {}
        guard case .manual = result else { return XCTFail("Expected manual fallback") }
        XCTAssertEqual(writer.texts, ["selected"])
        XCTAssertTrue(environment.posted.isEmpty)
    }
}
