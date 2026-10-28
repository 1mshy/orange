import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "circle.hexagongrid.circle", accessibilityDescription: "Orange")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let header = NSMenuItem(title: "Orange \(version)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Operations…", action: #selector(showOperations), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Float Shelf…", action: #selector(showShelf), keyEquivalent: "f").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "How It Works…", action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Orange", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func showOperations() { OperationProgressWindowController.shared.show() }
    @objc private func showShelf() { FloatShelfController.shared.show() }
    @objc private func showSettings() { SettingsWindowController.shared.show() }
    @objc private func showWelcome() { WelcomeWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
