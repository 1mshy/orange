import SwiftUI

enum CompressionMode: String, CaseIterable, Identifiable { case preset, targetSize, percentage; var id: String { rawValue }
    var title: String { switch self { case .preset: return "Preset"; case .targetSize: return "Target size"; case .percentage: return "Reduce by %" } } }
enum CompressionStrength: String, CaseIterable, Identifiable { case light, balanced, strong; var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var imageQuality: Double { switch self { case .light: return 0.8; case .balanced: return 0.6; case .strong: return 0.4 } }
    var crf: Int { switch self { case .light: return 24; case .balanced: return 28; case .strong: return 33 } }
    var audioBitrate: Int { switch self { case .light: return 160; case .balanced: return 128; case .strong: return 96 } } }
enum AspectPreset: String, CaseIterable, Identifiable { case original, square, r4x3, r3x2, r16x9, r9x16, custom; var id: String { rawValue }
    var title: String { switch self { case .original: return "Original"; case .square: return "1:1"; case .r4x3: return "4:3"; case .r3x2: return "3:2"; case .r16x9: return "16:9"; case .r9x16: return "9:16"; case .custom: return "Custom" } }
    var ratio: CGFloat? { switch self { case .original, .custom: return nil; case .square: return 1; case .r4x3: return 4/3; case .r3x2: return 3/2; case .r16x9: return 16/9; case .r9x16: return 9/16 } } }
enum RedactionKind: String, CaseIterable, Identifiable { case faces, text, both; var id: String { rawValue }; var title: String { rawValue.capitalized } }
enum RedactionStyle: String, CaseIterable, Identifiable { case solid, blur; var id: String { rawValue }; var title: String { rawValue.capitalized } }
enum SplitMode: String, CaseIterable, Identifiable { case separateFiles, everyPage; var id: String { rawValue } }
enum ChannelLayout: String, CaseIterable, Identifiable { case mono, stereo; var id: String { rawValue }; var title: String { rawValue.capitalized } }

/// All adjustable settings for every tool, edited in `ToolOptionsView`.
final class ToolOptions: ObservableObject {
    // Compress
    @Published var compressionMode: CompressionMode = .preset
    @Published var strength: CompressionStrength = .balanced
    @Published var targetSizeKB: Int = 500
    @Published var reductionPercent: Int = 50
    @Published var maxDimension: Int = 0          // 0 = keep
    // Metadata
    @Published var removeMetadata = true
    @Published var metaTitle = ""
    @Published var metaAuthor = ""
    @Published var metaCopyright = ""
    @Published var metaKeywords = ""
    // Edit
    @Published var exposure: Double = 0
    @Published var brightness: Double = 0
    @Published var contrast: Double = 1
    @Published var saturation: Double = 1
    @Published var sharpness: Double = 0
    // Background
    @Published var backgroundColor: Color = .white
    @Published var padding: Double = 48
    @Published var cornerRadius: Double = 24
    @Published var aspect: AspectPreset = .original
    // Crop
    @Published var cropAspect: AspectPreset = .square
    @Published var cropX: Int = 0
    @Published var cropY: Int = 0
    @Published var cropWidth: Int = 0
    @Published var cropHeight: Int = 0
    // Redact
    @Published var redactionKind: RedactionKind = .faces
    @Published var redactionStyle: RedactionStyle = .solid
    // Trim / split / speed / snapshot
    @Published var startTime: Double = 0
    @Published var endTime: Double = 0
    @Published var splitPoints: String = ""
    @Published var pageRanges: String = ""
    @Published var speed: Double = 1.5
    @Published var snapshotTime: Double = 0
    // Audio
    @Published var loudness: Double = -14
    @Published var channels: ChannelLayout = .stereo
    // Rotate
    @Published var rotation: Int = 90
    // Collage
    @Published var columns: Int = 2
    @Published var spacing: Double = 12
    @Published var collageBackground: Color = .white
    @Published var collageCornerRadius: Double = 12
    // Merge
    @Published var mergeSorted = true
}
