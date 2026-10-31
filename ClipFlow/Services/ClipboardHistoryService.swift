import Combine
import Foundation

@MainActor
final class ClipboardHistoryService: ObservableObject {
    nonisolated static let capacity = 10
    nonisolated static let maximumBytes = 100 * 1024
    @Published private(set) var items: [ClipboardItem] = []

    func add(_ text: String, at date: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= Self.maximumBytes else { return }
        let existing = items.first { $0.text == text }
        items.removeAll { $0.text == text }
        items.insert(ClipboardItem(id: existing?.id ?? UUID(), text: text, copiedAt: date), at: 0)
        items = Array(items.prefix(Self.capacity))
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    func clear() { items.removeAll() }

    func matching(_ query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
}
