import Foundation
import PDFKit
import AppKit

struct DocumentConverter: Converter {
    static let outputs: Set<String> = ["pdf", "docx", "rtf", "rtfd", "md", "txt", "html", "epub"]

    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool {
        (category == .document || category == .epub) && Self.outputs.contains(target.ext)
    }

    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let destination = OutputNaming.destination(for: source, in: outputDirectory, ext: target.ext)
        // Pages → PDF can reuse the package's own preview PDF losslessly.
        if source.pathExtension.lowercased() == "pages", target.ext == "pdf", let preview = DocumentIO.pagesPreviewPDF(source) {
            try FileManager.default.copyItem(at: preview, to: destination)
            return [destination]
        }
        if source.pathExtension.lowercased() == "doc" || source.pathExtension.lowercased() == "odt", ToolLocator.url(for: .soffice) != nil, target.ext == "pdf" || target.ext == "docx" {
            return try await OfficeConverter().convert(source: source, target: target, outputDirectory: outputDirectory, progress: progress)
        }
        progress(0.2)
        let attr = try DocumentIO.read(source)
        progress(0.6)
        try DocumentIO.write(attr, to: destination, ext: target.ext)
        progress(1)
        return [destination]
    }
}
