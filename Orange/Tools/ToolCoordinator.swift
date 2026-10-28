import SwiftUI
import AppKit

/// Shows the options window for a tool and runs it.
@MainActor
final class ToolCoordinator {
    static let shared = ToolCoordinator()
    private var windows: [NSWindow] = []

    func present(tool: FileTool, files: [URL]) {
        let options = ToolOptions()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "\(tool.name.capitalized) · \(files.count == 1 ? files[0].lastPathComponent : "\(files.count) files")"
        window.isReleasedWhenClosed = false
        let view = ToolOptionsView(tool: tool, files: files, options: options) { [weak self, weak window] in
            window?.close()
            if let window { self?.windows.removeAll { $0 == window } }
            self?.run(tool: tool, files: files, options: options)
        } onCancel: { [weak self, weak window] in
            window?.close()
            if let window { self?.windows.removeAll { $0 == window } }
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func run(tool: FileTool, files: [URL], options: ToolOptions) {
        guard let first = files.first, let directory = OutputNaming.outputDirectory(for: first) else { return }
        let title = "\(tool.name.capitalized): \(files.count == 1 ? first.lastPathComponent : "\(files.count) files")"
        let id = OperationCenter.shared.start(title)
        Task.detached(priority: .userInitiated) {
            do {
                let outputs = try await ToolRunner.run(tool, files: files, options: options, outputDirectory: directory) { value in
                    Task { @MainActor in OperationCenter.shared.progress(id, value) }
                }
                await MainActor.run { OperationCenter.shared.finish(id, outputs: outputs) }
            } catch {
                await MainActor.run { OperationCenter.shared.fail(id, error) }
            }
        }
    }
}

struct ToolOptionsView: View {
    let tool: FileTool
    let files: [URL]
    @ObservedObject var options: ToolOptions
    var onRun: () -> Void
    var onCancel: () -> Void

    private var category: FileCategory { FormatCatalog.category(of: files[0]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: tool.symbol).font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text(tool.name.capitalized).font(.headline)
                    Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                }
            }.padding()
            Divider()
            Form { fields }
                .formStyle(.grouped)
            Divider()
            HStack {
                Text(files.count == 1 ? files[0].lastPathComponent : "\(files.count) files").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Run", action: onRun).keyboardShortcut(.defaultAction)
            }.padding()
        }
        .frame(width: 460)
    }

    @ViewBuilder private var fields: some View {
        switch tool.id {
        case "compress":
            Picker("Mode", selection: $options.compressionMode) { ForEach(CompressionMode.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            switch options.compressionMode {
            case .preset: Picker("Strength", selection: $options.strength) { ForEach(CompressionStrength.allCases) { Text($0.title).tag($0) } }
            case .targetSize: TextField("Target size (KB)", value: $options.targetSizeKB, format: .number)
            case .percentage: Stepper("Reduce by \(options.reductionPercent)%", value: $options.reductionPercent, in: 1...99)
            }
            if category == .image || category == .video {
                TextField("Max dimension in pixels (0 keeps size)", value: $options.maxDimension, format: .number)
            }
        case "metadata":
            Toggle("Remove all metadata", isOn: $options.removeMetadata)
            if !options.removeMetadata {
                TextField("Title", text: $options.metaTitle)
                TextField("Author / artist", text: $options.metaAuthor)
                TextField("Copyright", text: $options.metaCopyright)
                if category != .audio && category != .video { TextField("Keywords (comma separated)", text: $options.metaKeywords) }
            }
        case "edit":
            slider("Exposure", $options.exposure, -2...2)
            slider("Brightness", $options.brightness, -0.5...0.5)
            slider("Contrast", $options.contrast, 0.5...1.5)
            slider("Saturation", $options.saturation, 0...2)
            slider("Sharpness", $options.sharpness, 0...2)
        case "background":
            ColorPicker("Background color", selection: $options.backgroundColor)
            slider("Padding", $options.padding, 0...400)
            slider("Corner radius", $options.cornerRadius, 0...200)
            Picker("Aspect ratio", selection: $options.aspect) { ForEach(AspectPreset.allCases.filter { $0 != .custom }) { Text($0.title).tag($0) } }
        case "crop":
            Picker("Aspect ratio", selection: $options.cropAspect) { ForEach(AspectPreset.allCases.filter { $0 != .original }) { Text($0.title).tag($0) } }
            if options.cropAspect == .custom {
                HStack { TextField("X", value: $options.cropX, format: .number); TextField("Y", value: $options.cropY, format: .number) }
                HStack { TextField("Width", value: $options.cropWidth, format: .number); TextField("Height", value: $options.cropHeight, format: .number) }
                Text("Pixels from the top-left corner. 0 width or height keeps the full size.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("The crop is centered.").font(.caption).foregroundStyle(.secondary)
            }
        case "redact":
            Picker("Detect", selection: $options.redactionKind) { ForEach(RedactionKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Picker("Style", selection: $options.redactionStyle) { ForEach(RedactionStyle.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Text("Blur softens details. Use Solid for sensitive information. Detection runs locally with Vision.").font(.caption).foregroundStyle(.secondary)
        case "createpdf":
            Text("\(files.count) images become one PDF with a page per image, in the dragged order.")
        case "collage":
            Stepper("Columns: \(options.columns)", value: $options.columns, in: 1...6)
            slider("Spacing", $options.spacing, 0...80)
            slider("Corner radius", $options.collageCornerRadius, 0...80)
            ColorPicker("Background", selection: $options.collageBackground)
        case "trim":
            TextField("Start (seconds or mm:ss)", value: $options.startTime, format: .number)
            TextField("End (seconds, 0 = end of file)", value: $options.endTime, format: .number)
        case "split":
            if category == .pdf {
                TextField("Page ranges, e.g. 1-3, 5, 8-10 (empty = every page)", text: $options.pageRanges)
            } else {
                TextField("Split points in seconds, e.g. 30, 1:05, 120", text: $options.splitPoints)
            }
        case "merge":
            Toggle("Sort by file name", isOn: $options.mergeSorted)
            Text(category == .video ? "Clips are scaled to the first clip's size and re-encoded to MP4." : "Files are joined in order.").font(.caption).foregroundStyle(.secondary)
        case "snapshot":
            TextField("Time in seconds", value: $options.snapshotTime, format: .number)
        case "speed":
            slider("Speed ×", $options.speed, 0.25...4)
        case "normalize":
            slider("Target loudness (LUFS)", $options.loudness, -30...(-8))
        case "channels":
            Picker("Channels", selection: $options.channels) { ForEach(ChannelLayout.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        case "rotate":
            Picker("Rotation", selection: $options.rotation) { Text("90° clockwise").tag(90); Text("180°").tag(180); Text("90° counter-clockwise").tag(270) }
        case "mute":
            Text("The video stream is copied without re-encoding; the audio track is dropped.")
        default:
            Text("This tool has no adjustable settings.")
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 150, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }
    }
}
