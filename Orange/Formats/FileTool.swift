import Foundation

/// An advanced file tool (Command wheel). Availability depends on the
/// category of the dragged selection and on how many files were dragged.
struct FileTool: Hashable, Identifiable {
    enum Multiplicity { case single, any, multipleRequired }
    let id: String
    let name: String
    let symbol: String
    let categories: Set<FileCategory>
    let multiplicity: Multiplicity
    let summary: String
}

enum Tools {
    static let compress = FileTool(id: "compress", name: "COMPRESS", symbol: "arrow.down.right.and.arrow.up.left", categories: [.image, .video, .audio, .pdf], multiplicity: .any, summary: "Choose a target file size, quality, or preset. Resize while compressing.")
    static let metadata = FileTool(id: "metadata", name: "METADATA", symbol: "tag", categories: [.image, .video, .audio, .pdf], multiplicity: .any, summary: "Edit title, author and copyright, or remove all metadata.")
    static let edit = FileTool(id: "edit", name: "EDIT", symbol: "slider.horizontal.3", categories: [.image], multiplicity: .any, summary: "Adjust exposure, contrast, saturation and sharpness.")
    static let addBackground = FileTool(id: "background", name: "ADD BG", symbol: "rectangle.inset.filled", categories: [.image], multiplicity: .any, summary: "Place a photo on a solid color with padding, aspect ratio and corner radius.")
    static let crop = FileTool(id: "crop", name: "CROP", symbol: "crop", categories: [.image, .video], multiplicity: .any, summary: "Crop to an aspect ratio or exact pixel rectangle.")
    static let redact = FileTool(id: "redact", name: "REDACT", symbol: "eye.slash", categories: [.image], multiplicity: .single, summary: "Detect faces or text locally, then cover them with a solid color or blur.")
    static let createPDF = FileTool(id: "createpdf", name: "CREATE PDF", symbol: "doc.on.doc", categories: [.image], multiplicity: .multipleRequired, summary: "Combine selected images into one PDF, one page per image.")
    static let collage = FileTool(id: "collage", name: "COLLAGE", symbol: "square.grid.2x2", categories: [.image], multiplicity: .multipleRequired, summary: "Combine images in a grid with spacing, corners and background.")
    static let trim = FileTool(id: "trim", name: "TRIM", symbol: "scissors", categories: [.video, .audio], multiplicity: .single, summary: "Keep a start and end range.")
    static let split = FileTool(id: "split", name: "SPLIT", symbol: "rectangle.split.2x1", categories: [.video, .audio, .pdf], multiplicity: .single, summary: "Split at time points or page ranges.")
    static let merge = FileTool(id: "merge", name: "MERGE", symbol: "rectangle.stack", categories: [.video, .audio, .pdf], multiplicity: .multipleRequired, summary: "Join the selected files into one.")
    static let snapshot = FileTool(id: "snapshot", name: "SNAPSHOT", symbol: "camera", categories: [.video], multiplicity: .single, summary: "Export one frame as a PNG.")
    static let speed = FileTool(id: "speed", name: "SPEED", symbol: "gauge.with.needle", categories: [.video, .audio], multiplicity: .any, summary: "Speed up or slow down playback.")
    static let normalize = FileTool(id: "normalize", name: "NORMALIZE", symbol: "waveform.path", categories: [.audio], multiplicity: .any, summary: "Normalize loudness to a target level.")
    static let channels = FileTool(id: "channels", name: "CHANNELS", symbol: "speaker.wave.2", categories: [.audio, .video], multiplicity: .any, summary: "Convert to mono or stereo.")
    static let rotate = FileTool(id: "rotate", name: "ROTATE", symbol: "rotate.right", categories: [.image, .pdf], multiplicity: .any, summary: "Rotate by 90-degree turns.")
    static let mute = FileTool(id: "mute", name: "MUTE", symbol: "speaker.slash", categories: [.video], multiplicity: .any, summary: "Remove the audio track.")

    static let all: [FileTool] = [compress, metadata, edit, addBackground, crop, redact, createPDF, collage, trim, split, merge, snapshot, speed, normalize, channels, rotate, mute]

    static func tools(for urls: [URL]) -> [FileTool] {
        let categories = Set(urls.map(FormatCatalog.category(of:)))
        guard categories.count == 1, let category = categories.first else { return [] }
        return all.filter { tool in
            guard tool.categories.contains(category) else { return false }
            switch tool.multiplicity {
            case .single: return urls.count == 1
            case .any: return true
            case .multipleRequired: return urls.count >= 2
            }
        }
    }
}
