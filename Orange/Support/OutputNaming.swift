import Foundation
import AppKit

enum OutputLocation: String, CaseIterable, Codable {
    case besideOriginal, downloads, ask
    var title: String {
        switch self {
        case .besideOriginal: return "Beside the original"
        case .downloads: return "Downloads folder"
        case .ask: return "Ask every time"
        }
    }
}

enum OutputNaming {
    /// Folder results are written to, honoring the output location setting.
    @MainActor
    static func outputDirectory(for source: URL) -> URL? {
        switch AppSettings.shared.outputLocation {
        case .besideOriginal: return source.deletingLastPathComponent()
        case .downloads: return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .ask:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Save Here"
            panel.message = "Choose where Orange should save the results."
            NSApp.activate(ignoringOtherApps: true)
            return panel.runModal() == .OK ? panel.url : nil
        }
    }

    /// A non-colliding path "name.ext", "name 2.ext", ... in `directory`.
    static func unique(in directory: URL, baseName: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        if ext.isEmpty { candidate = directory.appendingPathComponent(baseName) }
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = "\(baseName) \(n)"
            candidate = ext.isEmpty ? directory.appendingPathComponent(name) : directory.appendingPathComponent(name).appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    static func destination(for source: URL, in directory: URL, ext: String, suffix: String? = nil) -> URL {
        var base = source.deletingPathExtension().lastPathComponent
        if let suffix { base += " \(suffix)" }
        return unique(in: directory, baseName: base, ext: ext)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Orange-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
