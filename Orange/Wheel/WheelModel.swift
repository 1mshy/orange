import SwiftUI

@MainActor
final class WheelModel: ObservableObject {
    @Published var mode: WheelMode = .convert
    @Published var items: [WheelItem] = []
    @Published var selectedIndex: Int? = nil
    @Published var files: [URL] = []
    @Published var emptyMessage: String? = nil
    @Published var isVisible = false

    var categoryTitle: String {
        let categories = Set(files.map(FormatCatalog.category(of:)))
        if categories.count == 1, let c = categories.first {
            return files.count == 1 ? c.title : "\(files.count) \(c.title.lowercased())s"
        }
        return "\(files.count) items"
    }

    var selectedItem: WheelItem? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    func load(files: [URL], mode: WheelMode) {
        self.files = files
        self.mode = mode
        rebuild()
    }

    func switchMode(_ newMode: WheelMode) {
        guard newMode != mode else { return }
        mode = newMode
        rebuild()
    }

    private func rebuild() {
        selectedIndex = nil
        emptyMessage = nil
        switch mode {
        case .convert:
            items = FormatCatalog.targets(for: files).map { WheelItem(kind: .format($0)) }
            if items.isEmpty { emptyMessage = "No conversions for this selection" }
        case .tools:
            items = Tools.tools(for: files).map { WheelItem(kind: .tool($0)) }
            if items.isEmpty { emptyMessage = "No file tools for this selection" }
        case .actions:
            items = FileAction.allCases.map { WheelItem(kind: .action($0)) }
        }
    }

    /// Maps a point (in wheel-local coordinates, origin at the center, y up) to a petal.
    func select(atOffset offset: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) {
        let distance = hypot(offset.x, offset.y)
        guard !items.isEmpty, distance >= innerRadius * 0.9, distance <= outerRadius * 1.15 else {
            setSelection(nil); return
        }
        // Angle measured clockwise from the top.
        var angle = atan2(offset.x, offset.y)
        if angle < 0 { angle += 2 * .pi }
        let slice = 2 * .pi / CGFloat(items.count)
        let index = Int(((angle + slice / 2).truncatingRemainder(dividingBy: 2 * .pi)) / slice) % items.count
        setSelection(index)
    }

    func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = selectedIndex ?? (delta > 0 ? -1 : 0)
        let next = ((current + delta) % items.count + items.count) % items.count
        setSelection(next)
    }

    func setSelection(_ index: Int?) {
        guard index != selectedIndex else { return }
        selectedIndex = index
        if index != nil { SoundPlayer.highlight() }
    }
}
