import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Cliply

enum ClipboardImageFixture {
    static func data(type: UTType = .png, width: Int = 4, height: Int = 3, shade: UInt8 = 80) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: CGFloat(shade) / 255, green: 0.3, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func image(shade: UInt8 = 80, name: String? = nil) throws -> ClipboardImage {
        let encoded = try Self.data(shade: shade)
        return try XCTUnwrap(ClipboardImage.make(representations: [UTType.png.identifier: encoded], sourceName: name))
    }
}

final class ClipboardImageTests: XCTestCase {
    func testPreservesOriginalAndCreatesBoundedThumbnail() throws {
        let data = try ClipboardImageFixture.data(width: 1000, height: 600)
        let image = try XCTUnwrap(ClipboardImage.make(representations: [UTType.png.identifier: data]))
        XCTAssertEqual(image.representations[UTType.png.identifier], data)
        XCTAssertEqual(image.pixelWidth, 1000)
        XCTAssertEqual(image.pixelHeight, 600)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(image.thumbnailPNG as CFData, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), ClipboardLimits.thumbnailPixels)
    }

    func testTIFFAndJPEGAreStoredWithTheirOriginalTypes() throws {
        for type in [UTType.tiff, .jpeg] {
            let data = try ClipboardImageFixture.data(type: type)
            let image = try XCTUnwrap(ClipboardImage.make(representations: [type.identifier: data]))
            XCTAssertEqual(image.representations[type.identifier], data)
            XCTAssertNotNil(NSImage(data: image.thumbnailPNG))
        }
    }

    func testInvalidAndOversizedImageDataAreRejected() throws {
        XCTAssertNil(ClipboardImage.make(representations: [UTType.png.identifier: Data("not a PNG".utf8)]))
        var oversized = try ClipboardImageFixture.data()
        oversized.append(Data(count: ClipboardLimits.imageBytes + 1 - oversized.count))
        XCTAssertNil(ClipboardImage.make(representations: [UTType.png.identifier: oversized]))
    }

    func testRestoringImagePreservesPixelsAndSuppressesOwnWrite() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clipboard = SystemClipboard(pasteboard: board)
        let data = try ClipboardImageFixture.data()
        board.clearContents()
        board.setData(data, forType: .png)
        let content = try XCTUnwrap(clipboard.readContent())
        XCTAssertNotNil(content.image)
        XCTAssertNil(content.text)
        XCTAssertTrue(clipboard.replaceContent(content))
        XCTAssertEqual(board.data(forType: .png), data)
        XCTAssertNil(board.string(forType: .string))
        XCTAssertNil(clipboard.readContent())
        XCTAssertTrue(clipboard.isRestoredContentCurrent(content))
        board.clearContents()
        board.setString("new copy", forType: .string)
        XCTAssertFalse(clipboard.isRestoredContentCurrent(content))
    }

    func testScreenshotTIFFIsPreferredToAnAccompanyingStringAndSensitiveImagesAreIgnored() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        let tiff = try ClipboardImageFixture.data(type: .tiff)
        item.setData(tiff, forType: .tiff)
        item.setString("https://example.com/image", forType: .string)
        board.clearContents()
        board.writeObjects([item])
        let clipboard = SystemClipboard(pasteboard: board)
        let content = try XCTUnwrap(clipboard.readContent())
        XCTAssertEqual(content.image?.representations[UTType.tiff.identifier], tiff)
        let hidden = NSPasteboardItem()
        hidden.setData(tiff, forType: .tiff)
        hidden.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents()
        board.writeObjects([hidden])
        XCTAssertNil(clipboard.readContent())
    }

    func testCopiedImageFileIsSnapshottedAndSurvivesFileDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Screenshot.png")
        let data = try ClipboardImageFixture.data()
        try data.write(to: file)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        // Finder may attach a generic file icon with different pixels.
        item.setData(try ClipboardImageFixture.data(shade: 170), forType: .png)
        board.writeObjects([item])
        let clipboard = SystemClipboard(pasteboard: board)
        let content = try XCTUnwrap(clipboard.readContent())
        XCTAssertEqual(content.image?.sourceName, "Screenshot.png")
        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(clipboard.replaceContent(content))
        XCTAssertEqual(board.data(forType: .png), data)
        XCTAssertNil(board.string(forType: .fileURL))
    }

    func testTrackerOnlyReportsExternalImagesOnce() throws {
        let clipboard = MemoryClipboard()
        let tracker = ClipboardTracker(clipboard: clipboard)
        var values: [ClipboardContent] = []
        tracker.onContent = { values.append($0) }
        let image = ClipboardContent.image(try ClipboardImageFixture.image())
        clipboard.copyContent(image)
        tracker.poll(); tracker.poll()
        XCTAssertEqual(values, [image])
        XCTAssertTrue(tracker.restore(image))
        tracker.poll()
        XCTAssertEqual(values, [image])
    }

    func testMultipleImageRepresentationsRoundTripAndExternalImageChangesAreDetected() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let clipboard = SystemClipboard(pasteboard: board)
        let png = try ClipboardImageFixture.data()
        let tiff = try ClipboardImageFixture.data(type: .tiff)
        let image = try XCTUnwrap(ClipboardImage.make(representations: ["public.png": png, "public.tiff": tiff]))
        XCTAssertTrue(clipboard.replaceContent(.image(image)))
        XCTAssertEqual(board.data(forType: .png), png)
        XCTAssertEqual(board.data(forType: .tiff), tiff)
        XCTAssertTrue(clipboard.isRestoredContentCurrent(.image(image)))
        board.setData(try ClipboardImageFixture.data(shade: 150), forType: .png)
        XCTAssertFalse(clipboard.isRestoredContentCurrent(.image(image)))
    }
}

@MainActor
final class MixedClipboardHistoryTests: XCTestCase {
    func testImagesAndTextShareTheTenItemLimit() throws {
        let history = ClipboardHistoryService()
        for index in 1...6 { history.add("Text \(index)") }
        for shade in [UInt8(20), 40, 60, 80, 100] { history.add(.image(try ClipboardImageFixture.image(shade: shade))) }
        XCTAssertEqual(history.items.count, 10)
        XCTAssertEqual(history.items.compactMap(\.image).count, 5)
        XCTAssertEqual(history.items.last?.text, "Text 2")
    }

    func testDuplicateImageKeepsIdentityAndMovesToTop() throws {
        let history = ClipboardHistoryService()
        let image = try ClipboardImageFixture.image()
        history.add(.image(image))
        let id = try XCTUnwrap(history.items.first?.id)
        history.add("text")
        history.add(.image(image))
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(history.items.first?.id, id)
    }

    func testImageSearchAndSelectionUseTheSameFilteredItems() throws {
        let history = ClipboardHistoryService()
        let image = try ClipboardImageFixture.image(name: "Design.png")
        history.add("unrelated text")
        history.add(.image(image))
        for query in ["ИЗОБРАЖЕНИЕ", "screenshot", "Design", "png"] {
            XCTAssertEqual(history.matching(query).first?.image, image)
        }
        let model = ClipboardViewModel(history: history)
        model.prepareForOpen()
        model.query = "Design"
        var chosen: ClipboardItem?
        model.onChoose = { chosen = $0 }
        model.choose()
        XCTAssertEqual(chosen?.image, image)
    }

    func testMemoryBudgetEvictsOldItemsAndRejectsItemsBiggerThanBudget() throws {
        let image = try ClipboardImageFixture.image()
        let history = ClipboardHistoryService(memoryLimit: image.memoryCost + 5)
        history.add(.image(image))
        history.add("123456")
        XCTAssertEqual(history.items.compactMap(\.text), ["123456"])
        XCTAssertTrue(history.items.compactMap(\.image).isEmpty)
        let small = ClipboardHistoryService(memoryLimit: 10)
        small.add("kept")
        small.add(.image(image))
        XCTAssertEqual(small.items.compactMap(\.text), ["kept"])
    }
}
