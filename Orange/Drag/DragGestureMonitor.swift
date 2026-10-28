import AppKit
import Carbon.HIToolbox

/// Detects a Finder (or any app) file drag without Accessibility permission.
///
/// Reconstructed from Tangerine: the app keeps `NSPasteboard(name: .drag)`,
/// remembers its `changeCount` on left-mouse-down, and treats an increase while
/// the button is held as the start of a drag. Modifier taps and the few
/// navigation keys are read by polling `CGEventSource` state at 60 Hz, which
/// also catches the mouse-up that drag sessions swallow from global monitors.
@MainActor
final class DragGestureMonitor {
    enum Event {
        case dragBegan(urls: [URL], location: NSPoint)
        case modifierTapped(ModifierKey)
        case keyPressed(Int)
        case dragEnded
    }

    var handler: ((Event) -> Void)?

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var monitors: [Any] = []
    private var timer: DispatchSourceTimer?
    private var changeCountBeforeMouseDown = 0
    private var mouseDown = false
    private var dragging = false
    private var previousFlags: CGEventFlags = []
    private var previousKeys: Set<Int> = []
    private let watchedKeys = [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Space]

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event); return event
        }) { monitors.append(local) }
        changeCountBeforeMouseDown = dragPasteboard.changeCount
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        stopPolling()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            changeCountBeforeMouseDown = dragPasteboard.changeCount
            mouseDown = true
            dragging = false
            startPolling()
        case .leftMouseDragged:
            if mouseDown && !dragging { checkForDrag() }
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
    }

    private func checkForDrag() {
        guard dragPasteboard.changeCount != changeCountBeforeMouseDown else { return }
        changeCountBeforeMouseDown = dragPasteboard.changeCount
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (dragPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        dragging = true
        previousFlags = CGEventSource.flagsState(.combinedSessionState)
        previousKeys = pressedKeys()
        handler?(.dragBegan(urls: urls, location: NSEvent.mouseLocation))
    }

    private func startPolling() {
        stopPolling()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 1.0 / 60.0, leeway: .milliseconds(4))
        source.setEventHandler { [weak self] in self?.poll() }
        source.resume()
        timer = source
    }

    private func stopPolling() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard mouseDown else { stopPolling(); return }
        guard CGEventSource.buttonState(.combinedSessionState, button: .left) else { endDrag(); return }
        if !dragging { checkForDrag(); return }

        let flags = CGEventSource.flagsState(.combinedSessionState)
        for key in ModifierKey.allCases where flags.contains(key.cgFlag) && !previousFlags.contains(key.cgFlag) {
            handler?(.modifierTapped(key))
        }
        previousFlags = flags

        let keys = pressedKeys()
        for code in keys.subtracting(previousKeys) { handler?(.keyPressed(code)) }
        previousKeys = keys
    }

    private func pressedKeys() -> Set<Int> {
        var pressed = Set<Int>()
        for code in watchedKeys where CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)) { pressed.insert(code) }
        return pressed
    }

    private func endDrag() {
        stopPolling()
        mouseDown = false
        guard dragging else { return }
        dragging = false
        handler?(.dragEnded)
    }
}
