import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardLimits {
    static let textBytes = 100 * 1024
    static let imageBytes = 64 * 1024 * 1024
    static let historyBytes = 128 * 1024 * 1024
    static let imagePixels = 40_000_000
    static let thumbnailPixels = 256
}

// Encoded originals and a small preview only. Never retain a full-resolution decoded bitmap.
struct ClipboardImage: Equatable, Sendable {
    let representations: [String: Data]
    let pixelWidth: Int
    let pixelHeight: Int
    let thumbnailPNG: Data
    let sourceName: String?
    private let fingerprint: Data

    var byteCount: Int { representations.values.reduce(0) { $0 + $1.count } }
    var memoryCost: Int { byteCount + thumbnailPNG.count }

    static func == (lhs: ClipboardImage, rhs: ClipboardImage) -> Bool {
        lhs.fingerprint == rhs.fingerprint
    }

    // Called on the clipboard worker queue. Metadata checks precede bounded thumbnail decoding.
    static func make(representations: [String: Data], sourceName: String? = nil) -> ClipboardImage? {
        let priority = [UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier]
        let ordered = representations.keys.sorted {
            let left = priority.firstIndex(of: $0) ?? priority.count
            let right = priority.firstIndex(of: $1) ?? priority.count
            return left == right ? $0 < $1 : left < right
        }
        var accepted: [String: Data] = [:]
        var totalBytes = 0
        var primarySource: CGImageSource?
        var primaryData: Data?
        var primaryType = ""
        var width = 0
        var height = 0
        var thumbnail: CGImage?
        for type in ordered {
            guard let data = representations[type], !data.isEmpty,
                  data.count <= ClipboardLimits.imageBytes - totalBytes,
                  let declared = UTType(type), declared.conforms(to: .image),
                  let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) > 0,
                  let detected = CGImageSourceGetType(source),
                  let detectedType = UTType(detected as String), detectedType.conforms(to: declared),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let imageWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let imageHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  imageWidth > 0, imageHeight > 0,
                  imageWidth <= ClipboardLimits.imagePixels / imageHeight else { continue }
            // Alternative representations of an item must describe the same image geometry.
            if primarySource != nil && (width != imageWidth || height != imageHeight) { continue }
            if primarySource == nil {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: ClipboardLimits.thumbnailPixels,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
                primarySource = source
                primaryData = data
                primaryType = detectedType.identifier
                width = imageWidth
                height = imageHeight
                thumbnail = preview
            }
            accepted[type] = data
            totalBytes += data.count
        }
        guard let primaryData, let thumbnail else { return nil }
        let previewData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(previewData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        var hasher = SHA256()
        hasher.update(data: Data(primaryType.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: primaryData)
        return ClipboardImage(representations: accepted, pixelWidth: width, pixelHeight: height,
                              thumbnailPNG: previewData as Data, sourceName: sourceName, fingerprint: Data(hasher.finalize()))
    }

    func matches(_ query: String) -> Bool {
        let formats = representations.keys.compactMap { UTType($0)?.preferredFilenameExtension }.joined(separator: " ")
        let types = representations.keys.joined(separator: " ")
        let keywords = "image picture screenshot изображение картинка скриншот скрин \(pixelWidth) \(pixelHeight) \(formats) \(types) \(sourceName ?? "")"
        return keywords.localizedCaseInsensitiveContains(query)
    }
}
