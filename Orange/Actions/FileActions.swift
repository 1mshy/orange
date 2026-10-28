import AppKit

/// The six Control-wheel actions.
@MainActor
enum FileActions {
    static func perform(_ action: FileAction, on files: [URL]) {
        switch action {
        case .airdrop:
            guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: files)
        case .float:
            FloatShelfController.shared.add(files)
        case .copy:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(files as [NSURL])
        case .move:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Move Here"
            panel.message = "Choose where to move \(files.count == 1 ? files[0].lastPathComponent : "\(files.count) items")."
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            let id = OperationCenter.shared.start("Move to \(destination.lastPathComponent)")
            var moved: [URL] = []
            do {
                for file in files {
                    let target = OutputNaming.unique(in: destination, baseName: file.deletingPathExtension().lastPathComponent, ext: file.pathExtension)
                    try FileManager.default.moveItem(at: file, to: target)
                    moved.append(target)
                }
                OperationCenter.shared.finish(id, outputs: moved)
            } catch {
                OperationCenter.shared.fail(id, error)
            }
        case .copyPath:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(files.map(\.path).joined(separator: "\n"), forType: .string)
        case .terminal:
            guard let first = files.first, first.isFileURL else { return }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
            let folder = isDir.boolValue && !FormatCatalog.inputExtensions.values.contains(where: { $0.contains(first.pathExtension.lowercased()) }) ? first : first.deletingLastPathComponent()
            let app = AppSettings.shared.terminalApp
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
                let fallback = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.terminal.bundleIdentifier)!
                NSWorkspace.shared.open([folder], withApplicationAt: fallback, configuration: NSWorkspace.OpenConfiguration())
                return
            }
            NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
