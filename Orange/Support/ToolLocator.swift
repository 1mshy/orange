import Foundation

/// Finds optional command-line helpers. Tangerine ships ffmpeg and cwebp inside
/// its bundle; Orange looks in the bundle first and then in common install
/// locations so a Homebrew install works out of the box.
enum ToolLocator {
    enum Tool: String, CaseIterable {
        case ffmpeg, ffprobe, cwebp, exiftool, soffice, unar, unrar, zip, unzip, tar, gzip, ditto
    }

    private static var cache: [Tool: URL?] = [:]
    private static let lock = NSLock()

    static func url(for tool: Tool) -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[tool] { return cached }
        let found = locate(tool)
        cache[tool] = found
        return found
    }

    static func require(_ tool: Tool) throws -> URL {
        guard let url = url(for: tool) else { throw ConversionError.toolMissing(tool.rawValue) }
        return url
    }

    static func invalidate() { lock.lock(); cache.removeAll(); lock.unlock() }

    private static func locate(_ tool: Tool) -> URL? {
        let fm = FileManager.default
        var candidates: [String] = []
        var customFFmpeg = UserDefaults.standard.string(forKey: "ffmpegPath")
        if let env = ProcessInfo.processInfo.environment["ORANGE_FFMPEG"], !env.isEmpty { customFFmpeg = env }
        if tool == .ffmpeg, let custom = customFFmpeg, !custom.isEmpty { candidates.append(custom) }
        if tool == .ffprobe, let custom = customFFmpeg, !custom.isEmpty {
            candidates.append((custom as NSString).deletingLastPathComponent + "/ffprobe")
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Tools/\(tool.rawValue)") { candidates.append(bundled.path) }
        if tool == .soffice {
            candidates.append("/Applications/LibreOffice.app/Contents/MacOS/soffice")
            candidates.append(("~/Applications/LibreOffice.app/Contents/MacOS/soffice" as NSString).expandingTildeInPath)
        }
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        candidates += dirs.map { "\($0)/\(tool.rawValue)" }
        for path in candidates where fm.isExecutableFile(atPath: path) {
            let url = URL(fileURLWithPath: path)
            // A Homebrew ffmpeg with a missing dylib still "exists"; make sure it launches.
            if (tool == .ffmpeg || tool == .ffprobe || tool == .cwebp) && !launches(url) { continue }
            return url
        }
        return nil
    }

    private static func launches(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { process.terminate(); return false }
        return process.terminationStatus == 0
    }
}
