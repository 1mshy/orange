import AppKit
import SwiftUI

/// Owns the wheel panel and ties the drag monitor, the model and the engines together.
@MainActor
final class WheelController {
    let model = WheelModel()
    private var panel: WheelPanel?
    private var dropView: WheelDropView?
    private var hostingView: NSHostingView<WheelView>?
    private var dropHandled = false
    private var pendingHide: DispatchWorkItem?

    private var outerRadius: CGFloat { AppSettings.shared.wheelRadius }
    private var innerRadius: CGFloat { max(48, outerRadius * 0.36) }
    private var panelSize: CGFloat { outerRadius * 2 + 60 }

    var isVisible: Bool { panel?.isVisible ?? false }

    func present(files: [URL], mode: WheelMode, at location: NSPoint) {
        pendingHide?.cancel()
        dropHandled = false
        model.load(files: files, mode: mode)
        model.isVisible = true
        let panel = makePanelIfNeeded()
        let size = panelSize
        var origin = NSPoint(x: location.x - size / 2, y: location.y - size / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - size)
            origin.y = min(max(origin.y, f.minY), f.maxY - size)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: size, height: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func switchMode(_ mode: WheelMode) {
        guard isVisible else { return }
        model.switchMode(mode)
    }

    func hide() {
        pendingHide?.cancel()
        guard let panel, panel.isVisible else { return }
        model.isVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    /// Called when the mouse button is released. If the drop landed on the wheel,
    /// `drop(urls:)` already ran; otherwise the wheel closes.
    func dragEnded() {
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.dropHandled else { return }
            self.hide()
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func handleKey(_ code: Int) {
        guard isVisible else { return }
        switch code {
        case 53: hide()                              // Escape
        case 123, 126: model.step(-1)               // Left / Up
        case 124, 125: model.step(1)                // Right / Down
        case 36, 76, 49:                            // Return / Enter / Space
            if let item = model.selectedItem { perform(item, on: model.files) }
        default: break
        }
    }

    func hover(offset: CGPoint?) {
        guard let offset else { model.setSelection(nil); return }
        model.select(atOffset: offset, outerRadius: outerRadius, innerRadius: innerRadius)
    }

    func drop(urls: [URL]) -> Bool {
        dropHandled = true
        let files = urls.isEmpty ? model.files : urls
        guard let item = model.selectedItem else { hide(); return false }
        perform(item, on: files)
        return true
    }

    private func perform(_ item: WheelItem, on files: [URL]) {
        hide()
        switch item.kind {
        case .format(let format):
            ConversionEngine.shared.convert(files, to: format)
        case .tool(let tool):
            ToolCoordinator.shared.present(tool: tool, files: files)
        case .action(let action):
            FileActions.perform(action, on: files)
        }
    }

    private func makePanelIfNeeded() -> WheelPanel {
        if let panel, hostingView != nil, panel.frame.width == panelSize { return panel }
        let panel = WheelPanel(size: panelSize)
        let drop = WheelDropView(frame: NSRect(x: 0, y: 0, width: panelSize, height: panelSize))
        drop.controller = self
        let hosting = NSHostingView(rootView: WheelView(model: model, outerRadius: outerRadius, innerRadius: innerRadius))
        hosting.frame = drop.bounds
        hosting.autoresizingMask = [.width, .height]
        drop.addSubview(hosting)
        panel.contentView = drop
        self.panel = panel
        self.dropView = drop
        self.hostingView = hosting
        return panel
    }
}
