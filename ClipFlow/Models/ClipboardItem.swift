import Foundation

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let copiedAt: Date

    init(id: UUID = UUID(), text: String, copiedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
    }

    var isURL: Bool {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text) else { return false }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
    }
}
