import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}

@MainActor
final class FloatShelfModel: ObservableObject {
    @Published var items: [ShelfItem] = []
    @Published var selection: Set<UUID> = []
    func add(_ urls: [URL]) {
        for url in urls where !items.contains(where: { $0.url == url }) { items.append(ShelfItem(url: url)) }
    }
    func remove(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) } }
}

/// A floating shelf (NSPanel) that keeps files handy and lets the user drag
/// them into another app. Pinned to the top of the window stack.
@MainActor
final class FloatShelfController: NSWindowController {
    static let shared = FloatShelfController()
    let model = FloatShelfModel()

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 360), styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Float"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.contentViewController = NSHostingController(rootView: FloatShelfView(model: model))
    }
    required init?(coder: NSCoder) { fatalError() }

    func add(_ urls: [URL]) {
        model.add(urls)
        show()
    }

    func show() {
        guard let window else { return }
        if window.frame.origin == .zero, let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - window.frame.width - 16, y: f.midY - window.frame.height / 2))
        }
        window.orderFront(nil)
    }
}

struct FloatShelfView: View {
    @ObservedObject var model: FloatShelfModel

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pin").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Drop files here, or tap Control while dragging and choose Float.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selection) {
                    ForEach(model.items) { item in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading) {
                                Text(item.url.lastPathComponent).lineLimit(1)
                                Text(item.url.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                        .contextMenu {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            Button("Open") { NSWorkspace.shared.open(item.url) }
                            Button("Remove") { model.remove([item.id]) }
                        }
                        .tag(item.id)
                    }
                }
                .onDeleteCommand { model.remove(model.selection) }
            }
            Divider()
            HStack {
                Text("\(model.items.count) item\(model.items.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.items.removeAll() }.disabled(model.items.isEmpty)
            }.padding(8)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in model.add([url]) }
                    }
                }
            }
            return true
        }
        .frame(minWidth: 240, minHeight: 200)
    }
}
