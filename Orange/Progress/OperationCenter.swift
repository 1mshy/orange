import Foundation
import SwiftUI
import AppKit

struct OperationItem: Identifiable {
    enum State: Equatable { case running, done, failed(String) }
    let id = UUID()
    var title: String
    var detail: String = ""
    var progress: Double = 0
    var state: State = .running
    var outputs: [URL] = []
}

@MainActor
final class OperationCenter: ObservableObject {
    static let shared = OperationCenter()
    @Published var items: [OperationItem] = []

    func start(_ title: String, detail: String = "") -> UUID {
        let item = OperationItem(title: title, detail: detail)
        items.insert(item, at: 0)
        OperationProgressWindowController.shared.showIfNeeded()
        return item.id
    }

    func progress(_ id: UUID, _ value: Double, detail: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progress = min(max(value, 0), 1)
        if let detail { items[index].detail = detail }
    }

    func finish(_ id: UUID, outputs: [URL]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progress = 1
        items[index].state = .done
        items[index].outputs = outputs
        items[index].detail = outputs.map(\.lastPathComponent).joined(separator: ", ")
        SoundPlayer.completed()
    }

    func fail(_ id: UUID, _ error: Error) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .failed(error.localizedDescription)
        items[index].detail = error.localizedDescription
    }

    func clearFinished() { items.removeAll { $0.state != .running } }
}

struct OperationListView: View {
    @ObservedObject var center = OperationCenter.shared
    var body: some View {
        VStack(spacing: 0) {
            if center.items.isEmpty {
                Text("No operations yet. Drag a file and tap a modifier key.")
                    .foregroundStyle(.secondary).padding(30)
            } else {
                List(center.items) { item in
                    HStack(spacing: 10) {
                        stateIcon(item.state)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.headline)
                            if item.state == .running {
                                ProgressView(value: item.progress).progressViewStyle(.linear)
                            }
                            Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if !item.outputs.isEmpty {
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting(item.outputs) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Clear finished") { center.clearFinished() }
            }.padding(8)
        }
        .frame(minWidth: 420, minHeight: 240)
    }

    @ViewBuilder private func stateIcon(_ state: OperationItem.State) -> some View {
        switch state {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

@MainActor
final class OperationProgressWindowController: NSWindowController {
    static let shared = OperationProgressWindowController()
    private init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300), styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Orange Operations"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OperationListView())
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
    func showIfNeeded() {
        guard let window, !window.isVisible else { return }
        if window.frame.origin == .zero, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.maxX - window.frame.width - 20, y: frame.maxY - window.frame.height - 20))
        }
        window.orderFront(nil)
    }
    func show() { showIfNeeded(); window?.orderFront(nil) }
}
