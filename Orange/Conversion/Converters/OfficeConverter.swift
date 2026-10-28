import Foundation
import PDFKit

/// Slides (PPT/PPTX/KEY/ODP), legacy Word/Excel and PDF→PPTX/XLSX go through
/// LibreOffice when it is installed. Tangerine ships a private JRE + Apache POI
/// for this; Orange delegates to the user's LibreOffice instead.
struct OfficeConverter: Converter {
    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool {
        let ext = source.pathExtension.lowercased()
        switch category {
        case .slides: return ["pdf", "jpg", "png", "pptx"].contains(target.ext) && ext != "key"
        case .spreadsheet: return ext == "xls" && ["xlsx", "ods", "csv", "tsv", "pdf"].contains(target.ext)
        case .document: return ["doc", "odt"].contains(ext) && ["pdf", "docx"].contains(target.ext)
        case .pdf: return ["pptx", "xlsx"].contains(target.ext)
        default: return false
        }
    }

    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let soffice = try ToolLocator.require(.soffice)
        let temp = try OutputNaming.temporaryDirectory()
        let intermediate = ["jpg", "png"].contains(target.ext) ? "pdf" : target.ext
        var filter = intermediate
        if source.pathExtension.lowercased() == "pdf" && target.ext == "pptx" { filter = "pptx:Impress MS PowerPoint 2007 XML" }
        if source.pathExtension.lowercased() == "pdf" && target.ext == "xlsx" { filter = "xlsx:Calc MS Excel 2007 XML" }
        var args = ["--headless", "--norestore", "--convert-to", filter, "--outdir", temp.path, source.path]
        if source.pathExtension.lowercased() == "pdf" { args.insert("--infilter=impress_pdf_import", at: 0) }
        progress(0.1)
        try await ProcessRunner.check(soffice, args, environment: ["HOME": temp.path])
        let produced = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil).first { $0.pathExtension.lowercased() == intermediate }
        guard let produced else { throw ConversionError.processFailed("LibreOffice", "no output file was produced") }
        progress(0.7)
        if ["jpg", "png"].contains(target.ext) {
            guard let doc = PDFDocument(url: produced) else { throw ConversionError.readFailed("intermediate PDF") }
            let base = source.deletingPathExtension().lastPathComponent
            let directory = doc.pageCount > 1 ? OutputNaming.unique(in: outputDirectory, baseName: "\(base) (\(target.name))", ext: "") : outputDirectory
            if doc.pageCount > 1 { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            return try PDFImages.render(doc, baseName: base, into: directory, ext: target.ext, dpi: 200)
        }
        if ["csv", "tsv"].contains(target.ext) {
            let workbook = try Spreadsheet.read(produced)
            return try Spreadsheet.write(workbook, to: OutputNaming.destination(for: source, in: outputDirectory, ext: target.ext), ext: target.ext)
        }
        let destination = OutputNaming.destination(for: source, in: outputDirectory, ext: target.ext)
        try FileManager.default.moveItem(at: produced, to: destination)
        return [destination]
    }
}
