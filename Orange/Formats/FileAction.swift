import Foundation

/// File actions (Control wheel). Work with any file, folder or mixed selection.
enum FileAction: String, CaseIterable, Identifiable {
    case airdrop, float, copy, move, copyPath, terminal
    var id: String { rawValue }
    var name: String {
        switch self {
        case .airdrop: return "AIRDROP"
        case .float: return "FLOAT"
        case .copy: return "COPY"
        case .move: return "MOVE"
        case .copyPath: return "COPY PATH"
        case .terminal: return "TERMINAL"
        }
    }
    var symbol: String {
        switch self {
        case .airdrop: return "airplayaudio"
        case .float: return "pin"
        case .copy: return "doc.on.doc"
        case .move: return "folder"
        case .copyPath: return "text.quote"
        case .terminal: return "terminal"
        }
    }
    var summary: String {
        switch self {
        case .airdrop: return "Share through the macOS recipient picker."
        case .float: return "Keep files in a floating shelf you can drag from later."
        case .copy: return "Copy files to the clipboard, ready to paste in Finder."
        case .move: return "Choose a destination folder and move the originals there."
        case .copyPath: return "Copy full paths as text, one per line."
        case .terminal: return "Open the folder in Terminal or iTerm2."
        }
    }
}
