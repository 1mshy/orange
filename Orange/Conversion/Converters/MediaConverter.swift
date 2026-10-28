import Foundation

/// Thin ffmpeg wrapper with encoder discovery and progress parsing
/// (`-progress pipe:1 -nostats`, the same mechanism Tangerine uses).
enum FFmpeg {
    private static var encoderCache: Set<String>?
    private static let lock = NSLock()

    static func hasEncoder(_ name: String) async -> Bool {
        lock.lock(); let cached = encoderCache; lock.unlock()
        if let cached { return cached.contains(name) }
        guard let ffmpeg = ToolLocator.url(for: .ffmpeg),
              let result = try? await ProcessRunner.run(ffmpeg, ["-hide_banner", "-encoders"]) else { return false }
        var set = Set<String>()
        for line in result.stdoutText.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0].count == 6 { set.insert(String(parts[1])) }
        }
        lock.lock(); encoderCache = set; lock.unlock()
        return set.contains(name)
    }

    static func pick(_ candidates: [String]) async -> String {
        for c in candidates where await hasEncoder(c) { return c }
        return candidates.first ?? ""
    }

    static func duration(of url: URL) async -> Double? {
        if let ffprobe = ToolLocator.url(for: .ffprobe),
           let result = try? await ProcessRunner.run(ffprobe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", url.path]),
           let value = Double(result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
        let info = await info(of: url)
        return info.duration > 0 ? info.duration : nil
    }

    struct StreamInfo { var width = 0, height = 0, hasVideo = false, hasAudio = false, duration = 0.0, bitrate = 0 }

    static func info(of url: URL) async -> StreamInfo {
        var info = StreamInfo()
        guard let ffprobe = ToolLocator.url(for: .ffprobe),
              let result = try? await ProcessRunner.run(ffprobe, ["-v", "error", "-show_entries", "stream=codec_type,width,height:format=duration,bit_rate", "-of", "default=noprint_wrappers=1", url.path]) else {
            return await infoViaFFmpeg(url)
        }
        for line in result.stdoutText.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "codec_type": if kv[1] == "video" { info.hasVideo = true } else if kv[1] == "audio" { info.hasAudio = true }
            case "width": if info.width == 0 { info.width = Int(kv[1]) ?? 0 }
            case "height": if info.height == 0 { info.height = Int(kv[1]) ?? 0 }
            case "duration": info.duration = Double(kv[1]) ?? 0
            case "bit_rate": info.bitrate = Int(kv[1]) ?? 0
            default: break
            }
        }
        return info
    }

    /// Without ffprobe, `ffmpeg -i` prints the same facts to stderr.
    static func infoViaFFmpeg(_ url: URL) async -> StreamInfo {
        var info = StreamInfo()
        guard let ffmpeg = ToolLocator.url(for: .ffmpeg),
              let result = try? await ProcessRunner.run(ffmpeg, ["-hide_banner", "-nostdin", "-i", url.path]) else { return info }
        for rawLine in result.stderrText.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Duration:") {
                let parts = line.components(separatedBy: ",")
                if let d = parts.first?.replacingOccurrences(of: "Duration:", with: "").trimmingCharacters(in: .whitespaces), let seconds = Subtitles.time(d) { info.duration = seconds }
                if let b = parts.first(where: { $0.contains("bitrate:") })?.replacingOccurrences(of: "bitrate:", with: "").trimmingCharacters(in: .whitespaces),
                   let kb = Int(b.components(separatedBy: " ").first ?? "") { info.bitrate = kb * 1000 }
            } else if line.hasPrefix("Stream #"), line.contains("Video:") {
                info.hasVideo = true
                if info.width == 0, let match = line.range(of: #"\b(\d{2,5})x(\d{2,5})\b"#, options: .regularExpression) {
                    let dims = line[match].split(separator: "x")
                    info.width = Int(dims[0]) ?? 0; info.height = Int(dims[1]) ?? 0
                }
            } else if line.hasPrefix("Stream #"), line.contains("Audio:") {
                info.hasAudio = true
            }
        }
        return info
    }

    /// Runs ffmpeg with the standard prefix; `inputs` are inserted as `-i` pairs.
    static func run(inputs: [URL], options: [String], output: URL, duration: Double?, progress: @escaping (Double) -> Void) async throws {
        let ffmpeg = try ToolLocator.require(.ffmpeg)
        var args = ["-hide_banner", "-nostdin", "-loglevel", "error", "-y"]
        for input in inputs { args += ["-i", input.path] }
        args += options
        args += ["-progress", "pipe:1", "-nostats", output.path]
        do {
            try await runChecked(ffmpeg, args, duration: duration, progress: progress)
        } catch {
            // ffmpeg leaves an empty or partial file behind on failure.
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    private static func runChecked(_ ffmpeg: URL, _ args: [String], duration: Double?, progress: @escaping (Double) -> Void) async throws {
        try await ProcessRunner.check(ffmpeg, args) { line in
            guard let duration, duration > 0 else { return }
            if line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") {
                if let value = Double(line.split(separator: "=").last ?? "") { progress(min(0.99, value / 1_000_000 / duration)) }
            } else if line == "progress=end" { progress(1) }
        }
    }

    static func run(input: URL, options: [String], output: URL, progress: @escaping (Double) -> Void) async throws {
        let duration = await duration(of: input)
        try await run(inputs: [input], options: options, output: output, duration: duration, progress: progress)
    }

    // MARK: Encoding recipes (reconstructed from the argument sets in Tangerine's binary)

    static func audioOptions(for ext: String) async -> [String] {
        switch ext {
        case "mp3": return ["-vn", "-c:a", "libmp3lame", "-b:a", "192k"]
        case "m4a": return ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case "wav": return ["-vn", "-c:a", "pcm_s16le"]
        case "flac": return ["-vn", "-c:a", "flac"]
        case "ogg": return ["-vn", "-c:a", await pick(["libvorbis", "vorbis"]), "-b:a", "192k"] + (await hasEncoder("libvorbis") ? [] : ["-strict", "experimental"])
        case "opus": return ["-vn", "-c:a", await pick(["libopus", "opus"]), "-b:a", "192k"] + (await hasEncoder("libopus") ? [] : ["-strict", "experimental"])
        case "aiff": return ["-vn", "-c:a", "pcm_s16be"]
        case "wma": return ["-vn", "-c:a", "wmav2", "-b:a", "192k"]
        default: return ["-vn"]
        }
    }

    static func videoOptions(for ext: String, source: StreamInfo) async -> [String] {
        let evenScale = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
        let h264 = await pick(["libx264", "h264_videotoolbox"])
        switch ext {
        case "mp4", "mov":
            var opts = ["-c:v", h264, "-pix_fmt", "yuv420p", "-vf", evenScale, "-movflags", "+faststart"]
            opts += h264 == "libx264" ? ["-preset", "medium", "-crf", "23"] : ["-b:v", "6M"]
            opts += source.hasAudio ? ["-c:a", "aac", "-b:a", "192k"] : ["-an"]
            return opts
        case "mkv":
            var opts = ["-c:v", h264, "-pix_fmt", "yuv420p", "-vf", evenScale]
            opts += h264 == "libx264" ? ["-preset", "medium", "-crf", "23"] : ["-b:v", "6M"]
            opts += source.hasAudio ? ["-c:a", "aac", "-b:a", "192k"] : ["-an"]
            return opts
        case "webm":
            let vp9 = await hasEncoder("libvpx-vp9")
            var opts = vp9 ? ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-deadline", "good", "-cpu-used", "2"] : ["-c:v", "libvpx", "-b:v", "4M"]
            opts += ["-pix_fmt", "yuv420p", "-vf", evenScale]
            opts += source.hasAudio ? ["-c:a", await pick(["libopus", "libvorbis"]), "-b:a", "128k"] : ["-an"]
            return opts
        case "avi":
            return ["-c:v", "mpeg4", "-q:v", "4", "-vf", evenScale] + (source.hasAudio ? ["-c:a", "libmp3lame", "-b:a", "192k"] : ["-an"])
        case "wmv":
            return ["-c:v", "wmv2", "-q:v", "4", "-vf", evenScale] + (source.hasAudio ? ["-c:a", "wmav2", "-b:a", "192k"] : ["-an"])
        case "gif":
            let width = min(source.width == 0 ? 480 : source.width, 640)
            return ["-vf", "fps=12,scale=\(width):-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5", "-loop", "0", "-an"]
        default:
            return []
        }
    }
}

struct MediaConverter: Converter {
    static let audioOutputs: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    static let videoOutputs: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"]

    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool {
        switch category {
        case .audio: return Self.audioOutputs.contains(target.ext)
        case .video: return Self.videoOutputs.contains(target.ext) || target.ext == "mp3"
        default: return false
        }
    }

    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        _ = try ToolLocator.require(.ffmpeg)
        let destination = OutputNaming.destination(for: source, in: outputDirectory, ext: target.ext)
        let info = await FFmpeg.info(of: source)
        let options: [String]
        if Self.audioOutputs.contains(target.ext) {
            options = await FFmpeg.audioOptions(for: target.ext)
        } else {
            options = await FFmpeg.videoOptions(for: target.ext, source: info)
        }
        try await FFmpeg.run(inputs: [source], options: options, output: destination, duration: info.duration > 0 ? info.duration : nil, progress: progress)
        return [destination]
    }
}
