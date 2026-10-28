import Foundation

struct SubtitleCue { var start: Double; var end: Double; var text: String }

enum Subtitles {
    static func parse(_ text: String) throws -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            if lines.first?.hasPrefix("WEBVTT") == true || lines.first?.hasPrefix("NOTE") == true || lines.first?.hasPrefix("STYLE") == true { continue }
            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count == 2, let start = time(parts[0]), let end = time(parts[1]) else { continue }
            let body = lines[(timeIndex + 1)...].joined(separator: "\n")
            cues.append(SubtitleCue(start: start, end: end, text: body))
        }
        guard !cues.isEmpty else { throw ConversionError.readFailed("No valid subtitle cues were found") }
        return cues
    }

    static func time(_ raw: String) -> Double? {
        let token = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let cleaned = token.replacingOccurrences(of: ",", with: ".")
        let pieces = cleaned.split(separator: ":").map(String.init)
        guard pieces.count >= 2, pieces.count <= 3 else { return nil }
        var seconds = 0.0
        for p in pieces { guard let v = Double(p) else { return nil }; seconds = seconds * 60 + v }
        return seconds
    }

    static func format(_ seconds: Double, srt: Bool) -> String {
        let total = max(0, seconds)
        let h = Int(total / 3600), m = Int(total.truncatingRemainder(dividingBy: 3600) / 60), s = Int(total.truncatingRemainder(dividingBy: 60))
        let ms = Int((total - floor(total)) * 1000 + 0.5) % 1000
        return String(format: srt ? "%02d:%02d:%02d,%03d" : "%02d:%02d:%02d.%03d", h, m, s, ms)
    }

    static func srt(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { i, c in "\(i + 1)\n\(format(c.start, srt: true)) --> \(format(c.end, srt: true))\n\(stripTags(c.text))" }.joined(separator: "\n\n") + "\n"
    }

    static func vtt(_ cues: [SubtitleCue]) -> String {
        "WEBVTT\n\n" + cues.map { c in "\(format(c.start, srt: false)) --> \(format(c.end, srt: false))\n\(c.text)" }.joined(separator: "\n\n") + "\n"
    }

    static func txt(_ cues: [SubtitleCue]) -> String {
        cues.map { stripTags($0.text).replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n") + "\n"
    }

    static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<(?!/?[biu]>)[^>]+>", with: "", options: .regularExpression)
    }
}

struct SubtitleConverter: Converter {
    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool {
        category == .subtitle && ["srt", "vtt", "txt"].contains(target.ext)
    }

    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let data = try Data(contentsOf: source)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw ConversionError.readFailed("The subtitle file is not valid UTF-8") }
        let cues = try Subtitles.parse(text)
        let destination = OutputNaming.destination(for: source, in: outputDirectory, ext: target.ext)
        let output: String
        switch target.ext {
        case "srt": output = Subtitles.srt(cues)
        case "vtt": output = Subtitles.vtt(cues)
        default: output = Subtitles.txt(cues)
        }
        try output.write(to: destination, atomically: true, encoding: .utf8)
        return [destination]
    }
}
