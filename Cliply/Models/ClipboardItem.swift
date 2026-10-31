import Foundation

enum ClipboardContent: Equatable, Sendable {
    case text(String)
    case image(ClipboardImage)

    var text: String? {
        if case .text(let text) = self { return text }
        return nil
    }

    var image: ClipboardImage? {
        if case .image(let image) = self { return image }
        return nil
    }

    var memoryCost: Int {
        switch self {
        case .text(let text): return text.utf8.count
        case .image(let image): return image.memoryCost
        }
    }

    var isSupported: Bool {
        switch self {
        case .text(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= ClipboardLimits.textBytes
        case .image(let image):
            return image.byteCount > 0 && image.byteCount <= ClipboardLimits.imageBytes
        }
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        switch self {
        case .text(let text): return text.localizedCaseInsensitiveContains(query)
        case .image(let image): return image.matches(query)
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let content: ClipboardContent
    let copiedAt: Date

    var text: String? { content.text }
    var image: ClipboardImage? { content.image }

    init(id: UUID = UUID(), text: String, copiedAt: Date = Date()) {
        self.init(id: id, content: .text(text), copiedAt: copiedAt)
    }

    init(id: UUID = UUID(), content: ClipboardContent, copiedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.copiedAt = copiedAt
    }

    var isURL: Bool {
        guard let text, !text.contains(where: \.isWhitespace), let url = URL(string: text) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
}
