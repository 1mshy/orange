import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var ffmpegStatus = ""

    var body: some View {
        Form {
            Section("Wheel shortcuts") {
                Picker("Convert formats", selection: $settings.convertModifier) { modifierOptions }
                Picker("File tools", selection: $settings.toolsModifier) { modifierOptions }
                Picker("File actions", selection: $settings.actionsModifier) { modifierOptions }
                Text("Start dragging a file, then tap the key. Release it and keep dragging; the wheel stays open until you drop or press Escape.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Output") {
                Picker("Save results", selection: $settings.outputLocation) {
                    ForEach(OutputLocation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Terminal", selection: $settings.terminalApp) {
                    ForEach(TerminalApp.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Play sounds", isOn: $settings.soundsEnabled)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Slider(value: $settings.wheelRadius, in: 110...220, step: 10) { Text("Wheel size") }
            }
            Section("Helper tools") {
                HStack {
                    TextField("ffmpeg path (optional)", text: Binding(get: { settings.ffmpegPath ?? "" }, set: { settings.ffmpegPath = $0.isEmpty ? nil : $0 }))
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url { settings.ffmpegPath = url.path }
                    }
                }
                ToolStatusRow(tool: .ffmpeg, note: "audio, video, GIF, AVIF")
                ToolStatusRow(tool: .cwebp, note: "WebP output")
                ToolStatusRow(tool: .soffice, note: "PowerPoint, Word .doc, Excel .xls")
                ToolStatusRow(tool: .unar, note: "RAR extraction")
                ToolStatusRow(tool: .exiftool, note: "extended metadata editing")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.bottom, 8)
    }

    private var modifierOptions: some View {
        ForEach(ModifierKey.allCases) { key in Text("\(key.symbol) \(key.title)").tag(key) }
    }
}

struct ToolStatusRow: View {
    let tool: ToolLocator.Tool
    let note: String
    var body: some View {
        let url = ToolLocator.url(for: tool)
        HStack {
            Image(systemName: url == nil ? "xmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(url == nil ? Color.secondary : Color.green)
            Text(tool.rawValue).font(.body.monospaced())
            Text(note).foregroundStyle(.secondary)
            Spacer()
            Text(url?.path ?? "not found").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Orange Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
