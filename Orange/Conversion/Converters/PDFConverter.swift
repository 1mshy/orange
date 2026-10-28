import Foundation
import PDFKit
import AppKit

enum PDFImages {
    /// Renders every page at `dpi` into `directory` as `base page N.ext`.
    static func render(_ doc: PDFDocument, baseName: String, into directory: URL, ext: String, dpi: CGFloat = 300, quality: Double = 0.9, progress: ((Double) -> Void)? = nil) throws -> [URL] {
        var outputs: [URL] = []
        let scale = dpi / 72
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let rotation = page.rotation
            let rotated = rotation % 180 != 0
            let w = Int((rotated ? bounds.height : bounds.width) * scale), h = Int((rotated ? bounds.width : bounds.height) * scale)
            guard w > 0, h > 0, w * h < 120_000_000, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw ConversionError.readFailed("PDF page \(i + 1) has invalid dimensions")
            }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            guard let image = ctx.makeImage() else { continue }
            let name = doc.pageCount == 1 ? baseName : "\(baseName) page \(i + 1)"
            let url = OutputNaming.unique(in: directory, baseName: name, ext: ext)
            try ImageIOWriter.write(image, to: url, ext: ext, quality: quality)
            outputs.append(url)
            progress?(Double(i + 1) / Double(doc.pageCount))
        }
        return outputs
    }
}

struct PDFConverter: Converter {
    static let outputs: Set<String> = ["jpg", "png", "webp", "tiff", "heic", "txt", "md", "docx", "rtf", "html", "epub"]

    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool {
        if category == .pdf { return Self.outputs.contains(target.ext) }
        if category == .image && target.ext == "pdf" { return true }
        return false
    }

    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        guard let doc = PDFDocument(url: source) else { throw ConversionError.readFailed("The PDF cannot be read, is empty, or is password-protected") }
        if doc.isLocked { throw ConversionError.readFailed("The PDF is password-protected") }
        let base = source.deletingPathExtension().lastPathComponent
        switch target.ext {
        case "jpg", "png", "tiff", "heic":
            let directory: URL
            if doc.pageCount > 1 {
                directory = OutputNaming.unique(in: outputDirectory, baseName: "\(base) (\(target.name))", ext: "")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } else { directory = outputDirectory }
            return try PDFImages.render(doc, baseName: base, into: directory, ext: target.ext, progress: progress)
        case "webp":
            let directory = doc.pageCount > 1 ? OutputNaming.unique(in: outputDirectory, baseName: "\(base) (WEBP)", ext: "") : outputDirectory
            if doc.pageCount > 1 { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            let pngs = try PDFImages.render(doc, baseName: base, into: try OutputNaming.temporaryDirectory(), ext: "png", progress: { progress($0 * 0.6) })
            var outputs: [URL] = []
            for (i, png) in pngs.enumerated() {
                let image = try await ImageLoader.cgImage(from: png)
                let url = OutputNaming.unique(in: directory, baseName: pngs.count == 1 ? base : "\(base) page \(i + 1)", ext: "webp")
                try await ExternalImageEncoders.encodeWebP(image, to: url)
                outputs.append(url)
            }
            return outputs
        case "txt":
            let destination = OutputNaming.destination(for: source, in: outputDirectory, ext: "txt")
            try (doc.string ?? "").write(to: destination, atomically: true, encoding: .utf8)
            return [destination]
        default:
            let destination = OutputNaming.destination(for: source, in: outputDirectory, ext: target.ext)
            let attr = DocumentIO.pdfAttributedString(doc)
            guard attr.length > 0 else { throw ConversionError.readFailed("This PDF has no extractable text (scanned pages need OCR)") }
            progress(0.5)
            try DocumentIO.write(attr, to: destination, ext: target.ext)
            return [destination]
        }
    }
}
