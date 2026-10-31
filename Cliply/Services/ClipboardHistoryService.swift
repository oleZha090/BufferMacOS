import Combine
import Foundation

@MainActor
final class ClipboardHistoryService: ObservableObject {
    nonisolated static let capacity = 10
    nonisolated static let maximumBytes = ClipboardLimits.textBytes
    @Published private(set) var items: [ClipboardItem] = []
    private let memoryLimit: Int

    init(memoryLimit: Int = ClipboardLimits.historyBytes) { self.memoryLimit = max(1, memoryLimit) }

    func add(_ text: String, at date: Date = Date()) {
        add(.text(text), at: date)
    }

    func add(_ content: ClipboardContent, at date: Date = Date()) {
        guard content.isSupported, content.memoryCost <= memoryLimit else { return }
        let existing = items.first { $0.content == content }
        var updated = items.filter { $0.content != content }
        updated.insert(ClipboardItem(id: existing?.id ?? UUID(), content: content, copiedAt: date), at: 0)
        var memoryCost = updated.reduce(0) { $0 + $1.content.memoryCost }
        while updated.count > Self.capacity || memoryCost > memoryLimit {
            memoryCost -= updated.removeLast().content.memoryCost
        }
        items = updated
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    func clear() { items.removeAll() }

    func matching(_ query: String) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        return items.filter { $0.content.matches(query) }
    }
}
