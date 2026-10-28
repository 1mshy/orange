import SwiftUI
import AppKit

struct WelcomeView: View {
    @ObservedObject var settings = AppSettings.shared
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text("Orange").font(.largeTitle.bold())
                    Text("The zero-click offline file converter.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                step(settings.convertModifier.symbol, "Convert formats", "Drag a file, tap \(settings.convertModifier.title), and drop it on a format.")
                step(settings.toolsModifier.symbol, "File tools", "Tap \(settings.toolsModifier.title) while dragging to compress, crop, trim, split, merge and more.")
                step(settings.actionsModifier.symbol, "File actions", "Tap \(settings.actionsModifier.title) for AirDrop, Float, Copy, Move, Copy Path and Terminal.")
            }
            Text("Release the key and keep dragging; the wheel stays open until you drop or press Escape. Use the arrow keys to choose and Return to apply. Everything runs locally on your Mac.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            Toggle("Launch Orange at login", isOn: $settings.launchAtLogin)
            Text("Audio and video need ffmpeg (brew install ffmpeg). WebP output needs cwebp (brew install webp). Orange checks Homebrew paths automatically.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Open Settings") { SettingsWindowController.shared.show() }
                Button("Get Started") { onDone() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func step(_ key: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key).font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Welcome to Orange"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: WelcomeView { [weak self] in
            AppSettings.shared.hasSeenWelcome = true
            self?.window?.close()
        })
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
