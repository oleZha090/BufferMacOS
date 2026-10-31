import Combine
import Foundation

@MainActor
final class ClipboardViewModel: ObservableObject {
    let history: ClipboardHistoryService
    @Published var query = "" { didSet { reconcileSelection(reset: true) } }
    @Published private(set) var selectedID: UUID?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published private(set) var focusToken = UUID()
    var onChoose: ((ClipboardItem) -> Void)?
    var onClear: (() -> Void)?
    private var subscription: AnyCancellable?

    init(history: ClipboardHistoryService) {
        self.history = history
        subscription = history.$items.sink { [weak self] items in
            guard let self else { return }
            let visible = items.filter { $0.content.matches(self.query) }
            if !visible.contains(where: { $0.id == self.selectedID }) { self.selectedID = visible.first?.id }
            self.objectWillChange.send()
        }
    }

    var items: [ClipboardItem] { history.matching(query) }

    func prepareForOpen() {
        query = ""
        errorMessage = nil
        reconcileSelection(reset: true)
        focusToken = UUID()
    }

    private func reconcileSelection(reset: Bool) {
        if reset || !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
    }

    func move(_ delta: Int) {
        guard !isProcessing, !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        selectedID = items[min(max(0, current + delta), items.count - 1)].id
    }

    func choose(_ item: ClipboardItem? = nil) {
        guard !isProcessing, let chosen = item ?? items.first(where: { $0.id == selectedID }) else { return }
        selectedID = chosen.id
        onChoose?(chosen)
    }

    func remove(_ item: ClipboardItem) { history.remove(item.id) }

    func clearHistory() {
        if let onClear { onClear() } else { history.clear() }
    }
}
