import Foundation
import ImageIO
import PDFKit
import AppKit

struct ImageConverter: Converter {
    static let outputs: Set<String> = ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "gif", "pdf"]

    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool {
        category == .image && Self.outputs.contains(target.ext)
    }

    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let destination = OutputNaming.destination(for: source, in: outputDirectory, ext: target.ext)
        progress(0.1)
        let image = try await ImageLoader.cgImage(from: source)
        progress(0.5)
        switch target.ext {
        case "webp":
            try await ExternalImageEncoders.encodeWebP(image, to: destination)
        case "avif":
            try await ExternalImageEncoders.encodeAVIF(image, to: destination)
        case "pdf":
            let pdf = PDFDocument()
            guard let page = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))) else {
                throw ConversionError.writeFailed("PDF page")
            }
            pdf.insert(page, at: 0)
            guard pdf.write(to: destination) else { throw ConversionError.writeFailed(destination.lastPathComponent) }
        case "gif":
            try ImageIOWriter.write(image, to: destination, ext: "gif", quality: nil)
        default:
            try ImageIOWriter.write(image, to: destination, ext: target.ext, quality: 0.9)
        }
        progress(1)
        return [destination]
    }
}
