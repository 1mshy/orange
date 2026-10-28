import Foundation

/// The conversion matrix. Inputs are classified by extension, targets are the
/// petals shown on the Convert wheel for that category.
enum FormatCatalog {
    static let inputExtensions: [FileCategory: Set<String>] = [
        .image: ["jpg", "jpeg", "png", "webp", "heic", "heif", "tiff", "tif", "avif", "bmp", "svg", "jp2", "ico", "icns", "psd", "dng", "cr2", "nef", "arw", "raf"],
        .video: ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif", "m4v", "mpg", "mpeg", "flv", "3gp", "ts", "mts"],
        .audio: ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "aif", "wma", "aac", "caf", "amr"],
        .pdf: ["pdf"],
        .document: ["docx", "doc", "pages", "md", "markdown", "txt", "text", "rtf", "rtfd", "html", "htm", "textclipping", "odt"],
        .slides: ["pptx", "ppt", "key", "odp"],
        .spreadsheet: ["xlsx", "xls", "ods", "csv", "tsv", "numbers"],
        .epub: ["epub"],
        .subtitle: ["srt", "vtt"],
        .archive: ["zip", "tar", "gz", "tgz", "rar", "7z", "bz2", "xz"],
    ]

    static func category(of url: URL) -> FileCategory {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            // Bundles such as .pages/.rtfd/.key/.numbers are directories on disk.
            let ext = url.pathExtension.lowercased()
            if ["pages", "rtfd", "key", "numbers", "textclipping"].contains(ext) { return category(forExtension: ext) }
            return .folder
        }
        return category(forExtension: url.pathExtension.lowercased())
    }

    static func category(forExtension ext: String) -> FileCategory {
        for (cat, exts) in inputExtensions where exts.contains(ext) { return cat }
        return .unknown
    }

    /// Targets offered for one source category, in wheel order.
    static func targets(for category: FileCategory) -> [FileFormat] {
        switch category {
        case .image: return [Formats.jpg, Formats.png, Formats.webp, Formats.heic, Formats.tiff, Formats.avif, Formats.bmp, Formats.pdf]
        case .video: return [Formats.mp4, Formats.mov, Formats.mkv, Formats.webm, Formats.avi, Formats.wmv, Formats.gif, Formats.mp3]
        case .audio: return [Formats.mp3, Formats.m4a, Formats.wav, Formats.flac, Formats.ogg, Formats.opus, Formats.aiff, Formats.wma]
        case .pdf: return [Formats.docx, Formats.pptx, Formats.xlsx, Formats.jpg, Formats.png, Formats.epub, Formats.txt, Formats.md, Formats.html, Formats.rtf]
        case .document: return [Formats.pdf, Formats.docx, Formats.md, Formats.txt, Formats.epub, Formats.html, Formats.rtf]
        case .slides: return [Formats.pdf, Formats.jpg, Formats.png]
        case .spreadsheet: return [Formats.xlsx, Formats.ods, Formats.csv, Formats.tsv, Formats.pdf]
        case .epub: return [Formats.pdf, Formats.docx, Formats.md, Formats.txt, Formats.html, Formats.rtf]
        case .subtitle: return [Formats.srt, Formats.vtt, Formats.txt]
        case .archive: return [Formats.extract, Formats.zip, Formats.tar, Formats.gzip]
        case .folder: return [Formats.zip, Formats.tar, Formats.gzip]
        case .unknown: return [Formats.zip, Formats.tar, Formats.gzip]
        }
    }

    /// Targets shared by every dragged file. Formats equal to the source
    /// extension are dropped for single-category selections.
    static func targets(for urls: [URL]) -> [FileFormat] {
        let categories = Set(urls.map(category(of:)))
        guard let first = categories.first else { return [] }
        var result = targets(for: first)
        for cat in categories.dropFirst() {
            let other = targets(for: cat)
            result = result.filter { other.contains($0) }
        }
        if categories.count == 1, urls.count >= 1 {
            let exts = Set(urls.map { $0.pathExtension.lowercased() })
            result = result.filter { !exts.contains($0.ext) && !($0.ext == "jpg" && exts.contains("jpeg")) }
        }
        return result
    }
}
