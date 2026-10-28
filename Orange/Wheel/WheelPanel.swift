import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the wheel and accepts the drop.
final class WheelPanel: NSPanel {
    init(size: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        animationBehavior = .utilityWindow
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// NSView that is registered for file drags and forwards hover/drop to the controller.
final class WheelDropView: NSView {
    weak var controller: WheelController?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func offset(for sender: NSDraggingInfo) -> CGPoint {
        let p = convert(sender.draggingLocation, from: nil)
        return CGPoint(x: p.x - bounds.midX, y: p.y - bounds.midY)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.hover(offset: offset(for: sender))
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.hover(offset: offset(for: sender))
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.hover(offset: nil)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        controller?.hover(offset: offset(for: sender))
        return controller?.drop(urls: urls) ?? false
    }
}
