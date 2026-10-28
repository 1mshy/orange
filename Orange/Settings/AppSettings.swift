import Foundation
import AppKit
import ServiceManagement
import Combine

/// A modifier key the user taps during a drag to open one of the wheels.
enum ModifierKey: String, CaseIterable, Codable, Identifiable {
    case shift, command, control, option
    var id: String { rawValue }
    var cgFlag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .command: return .maskCommand
        case .control: return .maskControl
        case .option: return .maskAlternate
        }
    }
    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        }
    }
    var title: String { rawValue.capitalized }
}

enum TerminalApp: String, CaseIterable, Codable, Identifiable {
    case terminal = "Terminal", iterm = "iTerm"
    var id: String { rawValue }
    var title: String { self == .terminal ? "Terminal" : "iTerm2" }
    var bundleIdentifier: String { self == .terminal ? "com.apple.Terminal" : "com.googlecode.iterm2" }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var convertModifier: ModifierKey { didSet { defaults.set(convertModifier.rawValue, forKey: "convertModifier") } }
    @Published var toolsModifier: ModifierKey { didSet { defaults.set(toolsModifier.rawValue, forKey: "toolsModifier") } }
    @Published var actionsModifier: ModifierKey { didSet { defaults.set(actionsModifier.rawValue, forKey: "actionsModifier") } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var outputLocation: OutputLocation { didSet { defaults.set(outputLocation.rawValue, forKey: "outputLocation") } }
    @Published var terminalApp: TerminalApp { didSet { defaults.set(terminalApp.rawValue, forKey: "terminalApp") } }
    @Published var ffmpegPath: String? { didSet { defaults.set(ffmpegPath, forKey: "ffmpegPath"); ToolLocator.invalidate() } }
    @Published var hasSeenWelcome: Bool { didSet { defaults.set(hasSeenWelcome, forKey: "hasSeenWelcome") } }
    @Published var wheelRadius: Double { didSet { defaults.set(wheelRadius, forKey: "wheelRadius") } }
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Login item change failed: \(error)")
            }
        }
    }

    private init() {
        convertModifier = ModifierKey(rawValue: defaults.string(forKey: "convertModifier") ?? "") ?? .shift
        toolsModifier = ModifierKey(rawValue: defaults.string(forKey: "toolsModifier") ?? "") ?? .command
        actionsModifier = ModifierKey(rawValue: defaults.string(forKey: "actionsModifier") ?? "") ?? .control
        soundsEnabled = defaults.object(forKey: "soundsEnabled") as? Bool ?? true
        outputLocation = OutputLocation(rawValue: defaults.string(forKey: "outputLocation") ?? "") ?? .besideOriginal
        terminalApp = TerminalApp(rawValue: defaults.string(forKey: "terminalApp") ?? "") ?? .terminal
        ffmpegPath = defaults.string(forKey: "ffmpegPath")
        hasSeenWelcome = defaults.bool(forKey: "hasSeenWelcome")
        wheelRadius = defaults.object(forKey: "wheelRadius") as? Double ?? 150
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func mode(for modifier: ModifierKey) -> WheelMode? {
        if modifier == convertModifier { return .convert }
        if modifier == toolsModifier { return .tools }
        if modifier == actionsModifier { return .actions }
        return nil
    }

    func modifier(for mode: WheelMode) -> ModifierKey {
        switch mode {
        case .convert: return convertModifier
        case .tools: return toolsModifier
        case .actions: return actionsModifier
        }
    }
}
