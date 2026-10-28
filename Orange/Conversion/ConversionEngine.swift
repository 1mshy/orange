import Foundation
import AppKit

protocol Converter {
    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool
    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL]
}

/// Routes each dragged file to the first converter that supports the target
/// and reports to the operation center.
@MainActor
final class ConversionEngine {
    static let shared = ConversionEngine()

    let converters: [Converter] = [
        ImageConverter(), MediaConverter(), PDFConverter(), DocumentConverter(), SpreadsheetConverter(),
        SubtitleConverter(), ArchiveConverter(), OfficeConverter(),
    ]

    func converter(for source: URL, target: FileFormat) -> Converter? {
        let category = FormatCatalog.category(of: source)
        return converters.first { $0.supports(source: source, category: category, target: target) }
    }

    func convert(_ files: [URL], to target: FileFormat) {
        guard let first = files.first, let directory = OutputNaming.outputDirectory(for: first) else { return }
        for file in files {
            let title = target.ext.isEmpty ? "Extract \(file.lastPathComponent)" : "\(file.lastPathComponent) → \(target.name)"
            let id = OperationCenter.shared.start(title)
            guard let converter = converter(for: file, target: target) else {
                OperationCenter.shared.fail(id, ConversionError.unsupported("\(file.pathExtension.uppercased()) to \(target.name)"))
                continue
            }
            Task.detached(priority: .userInitiated) {
                do {
                    let outputs = try await converter.convert(source: file, target: target, outputDirectory: directory) { value in
                        Task { @MainActor in OperationCenter.shared.progress(id, value) }
                    }
                    await MainActor.run { OperationCenter.shared.finish(id, outputs: outputs) }
                } catch {
                    await MainActor.run { OperationCenter.shared.fail(id, error) }
                }
            }
        }
    }
}
