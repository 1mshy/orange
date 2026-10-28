import Foundation

enum ConversionError: LocalizedError {
    case unsupported(String)
    case toolMissing(String)
    case processFailed(String, String)
    case readFailed(String)
    case writeFailed(String)
    case cancelled
    case invalidOptions(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let what): return "This conversion is not supported: \(what)."
        case .toolMissing(let tool):
            switch tool {
            case "ffmpeg", "ffprobe": return "ffmpeg is required for audio and video. Install it with `brew install ffmpeg` or set its path in Settings."
            case "cwebp": return "cwebp (libwebp) is required for WebP output. Install it with `brew install webp`."
            case "soffice": return "LibreOffice is required for this format. Install it from libreoffice.org."
            case "exiftool": return "ExifTool is required. Install it with `brew install exiftool`."
            case "unar": return "The Unarchiver's `unar` is required for RAR files. Install it with `brew install unar`."
            default: return "\(tool) is required but was not found."
            }
        case .processFailed(let tool, let message): return "\(tool) failed: \(message)"
        case .readFailed(let what): return "The source file could not be read: \(what)."
        case .writeFailed(let what): return "The output could not be written: \(what)."
        case .cancelled: return "Cancelled."
        case .invalidOptions(let what): return what
        }
    }
}
