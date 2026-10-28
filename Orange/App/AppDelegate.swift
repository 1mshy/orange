import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dragMonitor: DragGestureMonitor!
    private var wheel: WheelController!
    private var menuBar: MenuBarController?

    static func main() {
        if CommandLineMode.runIfRequested() { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dragMonitor = DragGestureMonitor()
        wheel = WheelController()
        menuBar = MenuBarController()
        dragMonitor.handler = { [weak self] event in self?.handle(event) }
        dragMonitor.start()
        if !AppSettings.shared.hasSeenWelcome {
            WelcomeWindowController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragMonitor.stop()
    }

    private func handle(_ event: DragGestureMonitor.Event) {
        let settings = AppSettings.shared
        switch event {
        case .dragBegan:
            // Nothing is shown until a modifier is tapped; remember the drag.
            pendingDrag = event
        case .modifierTapped(let key):
            guard let mode = settings.mode(for: key) else { return }
            if wheel.isVisible {
                wheel.switchMode(mode)
            } else if case .dragBegan(let urls, _)? = pendingDrag {
                wheel.present(files: urls, mode: mode, at: NSEvent.mouseLocation)
            }
        case .keyPressed(let code):
            wheel.handleKey(code)
        case .dragEnded:
            pendingDrag = nil
            wheel.dragEnded()
        }
    }

    private var pendingDrag: DragGestureMonitor.Event?
}
