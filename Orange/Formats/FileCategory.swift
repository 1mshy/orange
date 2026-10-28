import Foundation
import UniformTypeIdentifiers

/// Broad family a dragged file belongs to. Mirrors the groups Tangerine's wheel
/// uses (Images, Video, Audio, PDF, Documents, Slides, Spreadsheets, EPUB,
/// Subtitles, Archives) plus folder/unknown for file actions only.
enum FileCategory: String, CaseIterable, Codable, Hashable {
    case image, video, audio, pdf, document, slides, spreadsheet, epub, subtitle, archive, folder, unknown

    var title: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .pdf: return "PDF"
        case .document: return "Document"
        case .slides: return "Slides"
        case .spreadsheet: return "Spreadsheet"
        case .epub: return "EPUB"
        case .subtitle: return "Subtitles"
        case .archive: return "Archive"
        case .folder: return "Folder"
        case .unknown: return "File"
        }
    }

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .slides: return "rectangle.on.rectangle"
        case .spreadsheet: return "tablecells"
        case .epub: return "book"
        case .subtitle: return "captions.bubble"
        case .archive: return "archivebox"
        case .folder: return "folder"
        case .unknown: return "doc"
        }
    }
}

/// A concrete output (or input) format identified by its file extension.
struct FileFormat: Hashable, Identifiable, Codable {
    let ext: String
    let name: String
    let category: FileCategory
    var id: String { ext }
    var utType: UTType? { UTType(filenameExtension: ext) }
}

enum Formats {
    // Images
    static let jpg = FileFormat(ext: "jpg", name: "JPG", category: .image)
    static let png = FileFormat(ext: "png", name: "PNG", category: .image)
    static let webp = FileFormat(ext: "webp", name: "WEBP", category: .image)
    static let heic = FileFormat(ext: "heic", name: "HEIC", category: .image)
    static let tiff = FileFormat(ext: "tiff", name: "TIFF", category: .image)
    static let avif = FileFormat(ext: "avif", name: "AVIF", category: .image)
    static let bmp = FileFormat(ext: "bmp", name: "BMP", category: .image)
    static let gif = FileFormat(ext: "gif", name: "GIF", category: .video)
    // Audio
    static let mp3 = FileFormat(ext: "mp3", name: "MP3", category: .audio)
    static let m4a = FileFormat(ext: "m4a", name: "M4A", category: .audio)
    static let wav = FileFormat(ext: "wav", name: "WAV", category: .audio)
    static let flac = FileFormat(ext: "flac", name: "FLAC", category: .audio)
    static let ogg = FileFormat(ext: "ogg", name: "OGG", category: .audio)
    static let opus = FileFormat(ext: "opus", name: "OPUS", category: .audio)
    static let aiff = FileFormat(ext: "aiff", name: "AIFF", category: .audio)
    static let wma = FileFormat(ext: "wma", name: "WMA", category: .audio)
    // Video
    static let mp4 = FileFormat(ext: "mp4", name: "MP4", category: .video)
    static let mov = FileFormat(ext: "mov", name: "MOV", category: .video)
    static let mkv = FileFormat(ext: "mkv", name: "MKV", category: .video)
    static let webm = FileFormat(ext: "webm", name: "WEBM", category: .video)
    static let avi = FileFormat(ext: "avi", name: "AVI", category: .video)
    static let wmv = FileFormat(ext: "wmv", name: "WMV", category: .video)
    // Documents
    static let pdf = FileFormat(ext: "pdf", name: "PDF", category: .pdf)
    static let docx = FileFormat(ext: "docx", name: "DOCX", category: .document)
    static let rtf = FileFormat(ext: "rtf", name: "RTF", category: .document)
    static let md = FileFormat(ext: "md", name: "MD", category: .document)
    static let txt = FileFormat(ext: "txt", name: "TXT", category: .document)
    static let html = FileFormat(ext: "html", name: "HTML", category: .document)
    static let epub = FileFormat(ext: "epub", name: "EPUB", category: .epub)
    static let pptx = FileFormat(ext: "pptx", name: "PPTX", category: .slides)
    // Spreadsheets
    static let xlsx = FileFormat(ext: "xlsx", name: "XLSX", category: .spreadsheet)
    static let ods = FileFormat(ext: "ods", name: "ODS", category: .spreadsheet)
    static let csv = FileFormat(ext: "csv", name: "CSV", category: .spreadsheet)
    static let tsv = FileFormat(ext: "tsv", name: "TSV", category: .spreadsheet)
    // Subtitles
    static let srt = FileFormat(ext: "srt", name: "SRT", category: .subtitle)
    static let vtt = FileFormat(ext: "vtt", name: "VTT", category: .subtitle)
    // Archives
    static let zip = FileFormat(ext: "zip", name: "ZIP", category: .archive)
    static let tar = FileFormat(ext: "tar", name: "TAR", category: .archive)
    static let gzip = FileFormat(ext: "gz", name: "GZIP", category: .archive)
    static let extract = FileFormat(ext: "", name: "EXTRACT", category: .archive)
}
