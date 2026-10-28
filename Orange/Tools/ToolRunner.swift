import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import Quartz
import Vision
import ImageIO

/// Executes an advanced tool on a set of files and returns the produced files.
enum ToolRunner {
    static func run(_ tool: FileTool, files: [URL], options: ToolOptions, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let snapshot = await MainActor.run { ToolOptionsSnapshot(options) }
        switch tool.id {
        case "compress": return try await each(files, progress) { try await compress($0, snapshot, outputDirectory) }
        case "metadata": return try await each(files, progress) { try await metadata($0, snapshot, outputDirectory) }
        case "edit": return try await each(files, progress) { try await adjust($0, snapshot, outputDirectory) }
        case "background": return try await each(files, progress) { try await addBackground($0, snapshot, outputDirectory) }
        case "crop": return try await each(files, progress) { try await crop($0, snapshot, outputDirectory, progress) }
        case "redact": return try await each(files, progress) { try await redact($0, snapshot, outputDirectory) }
        case "createpdf": return [try await createPDF(files, outputDirectory)]
        case "collage": return [try await collage(files, snapshot, outputDirectory)]
        case "trim": return try await each(files, progress) { try await trim($0, snapshot, outputDirectory, progress) }
        case "split": return try await split(files[0], snapshot, outputDirectory, progress)
        case "merge": return [try await merge(files, snapshot, outputDirectory, progress)]
        case "snapshot": return try await each(files, progress) { try await captureFrame($0, snapshot, outputDirectory) }
        case "speed": return try await each(files, progress) { try await speed($0, snapshot, outputDirectory, progress) }
        case "normalize": return try await each(files, progress) { try await normalize($0, snapshot, outputDirectory, progress) }
        case "channels": return try await each(files, progress) { try await channels($0, snapshot, outputDirectory, progress) }
        case "rotate": return try await each(files, progress) { try await rotate($0, snapshot, outputDirectory) }
        case "mute": return try await each(files, progress) { try await mute($0, outputDirectory, progress) }
        default: throw ConversionError.unsupported(tool.name)
        }
    }

    private static func each(_ files: [URL], _ progress: @escaping (Double) -> Void, _ body: (URL) async throws -> [URL]) async throws -> [URL] {
        var outputs: [URL] = []
        for (i, file) in files.enumerated() {
            outputs += try await body(file)
            progress(Double(i + 1) / Double(files.count))
        }
        return outputs
    }

    private static func destination(_ source: URL, _ directory: URL, suffix: String, ext: String? = nil) -> URL {
        OutputNaming.destination(for: source, in: directory, ext: ext ?? source.pathExtension.lowercased(), suffix: suffix)
    }

    private static func ffmpegVideoBase(_ ext: String) async -> [String] {
        let info = FFmpeg.StreamInfo(width: 0, height: 0, hasVideo: true, hasAudio: true, duration: 0, bitrate: 0)
        var opts = await FFmpeg.videoOptions(for: ext, source: info)
        if opts.isEmpty { opts = ["-c:v", await FFmpeg.pick(["libx264", "h264_videotoolbox"]), "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"] }
        return opts
    }

    // MARK: Compress

    static func compress(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL) async throws -> [URL] {
        let category = FormatCatalog.category(of: source)
        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
        var targetBytes: Int? = nil
        if o.compressionMode == .targetSize { targetBytes = o.targetSizeKB * 1024 }
        if o.compressionMode == .percentage { targetBytes = sourceSize * (100 - o.reductionPercent) / 100 }
        if let targetBytes, targetBytes < 1024 { throw ConversionError.invalidOptions("Enter a target size of at least 1 KB.") }
        if let targetBytes, targetBytes >= sourceSize, sourceSize > 0 { throw ConversionError.invalidOptions("Target size cannot exceed the original file size.") }

        switch category {
        case .image:
            var image = try await ImageLoader.cgImage(from: source)
            if o.maxDimension > 0 { image = ImageIOWriter.resized(image, maxDimension: o.maxDimension) }
            var ext = source.pathExtension.lowercased()
            if ext == "jpeg" { ext = "jpg" }
            let lossy = ["jpg", "heic", "webp", "avif"].contains(ext)
            if !lossy && targetBytes != nil { ext = "jpg" } // PNG/TIFF/BMP cannot hit a byte target losslessly.
            let out = destination(source, dir, suffix: "compressed", ext: ext)
            if let targetBytes {
                var low = 0.05, high = 0.95, best: Data? = nil
                for _ in 0..<8 {
                    let q = (low + high) / 2
                    let data = try encode(image, ext: ext, quality: q)
                    if data.count <= targetBytes { best = data; low = q } else { high = q }
                }
                guard let best else { throw ConversionError.invalidOptions("The encoder could not meet this target. Try a larger size or a smaller dimension.") }
                try best.write(to: out)
            } else if ext == "png" {
                try ImageIOWriter.write(image, to: out, ext: "png", quality: nil)
                if o.maxDimension == 0 { try await PNGOptimizer.quantize(image, to: out) }
            } else if ext == "webp" {
                try await ExternalImageEncoders.encodeWebP(image, to: out, quality: Int(o.strength.imageQuality * 100))
            } else {
                try ImageIOWriter.write(image, to: out, ext: lossy ? ext : "jpg", quality: o.strength.imageQuality)
            }
            return [out]
        case .pdf:
            guard let doc = PDFDocument(url: source) else { throw ConversionError.readFailed("PDF") }
            let out = destination(source, dir, suffix: "compressed", ext: "pdf")
            let filterURL = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
            var written = false
            if let filter = QuartzFilter(url: filterURL) {
                written = doc.write(to: out, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter])
            }
            let outSize = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? Int.max
            if !written || outSize >= sourceSize {
                // Rasterize pages as JPEG at reduced DPI.
                let dpi: CGFloat = o.strength == .light ? 150 : (o.strength == .balanced ? 110 : 80)
                let temp = try OutputNaming.temporaryDirectory()
                let pages = try PDFImages.render(doc, baseName: "p", into: temp, ext: "jpg", dpi: dpi, quality: o.strength.imageQuality)
                let result = PDFDocument()
                for (i, url) in pages.enumerated() { if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) { result.insert(page, at: i) } }
                guard result.write(to: out) else { throw ConversionError.writeFailed("compressed PDF") }
            }
            return [out]
        case .video:
            let info = await FFmpeg.info(of: source)
            let ext = ["mp4", "mov", "mkv", "webm"].contains(source.pathExtension.lowercased()) ? source.pathExtension.lowercased() : "mp4"
            let out = destination(source, dir, suffix: "compressed", ext: ext)
            var opts: [String]
            let h264 = await FFmpeg.pick(["libx264", "h264_videotoolbox"])
            if let targetBytes, info.duration > 0 {
                let audioKbps = 96
                let totalKbps = Double(targetBytes) * 8 / info.duration / 1000
                let videoKbps = Int(totalKbps - Double(audioKbps) - totalKbps * 0.03)
                guard videoKbps > 50 else { throw ConversionError.invalidOptions("The target is too small for this duration. Choose a larger size.") }
                opts = ["-c:v", h264, "-b:v", "\(videoKbps)k", "-maxrate", "\(videoKbps)k", "-bufsize", "\(videoKbps * 2)k", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "\(audioKbps)k"]
            } else {
                opts = ["-c:v", h264, "-pix_fmt", "yuv420p"]
                opts += h264 == "libx264" ? ["-preset", "medium", "-crf", "\(o.strength.crf)"] : ["-b:v", o.strength == .light ? "4M" : (o.strength == .balanced ? "2M" : "1M")]
                opts += ["-c:a", "aac", "-b:a", "\(o.strength.audioBitrate)k"]
            }
            if o.maxDimension > 0 { opts += ["-vf", "scale='min(\(o.maxDimension),iw)':-2"] } else { opts += ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"] }
            if ext == "mp4" || ext == "mov" { opts += ["-movflags", "+faststart"] }
            try await FFmpeg.run(inputs: [source], options: opts, output: out, duration: info.duration) { _ in }
            return [out]
        case .audio:
            let info = await FFmpeg.info(of: source)
            let ext = ["mp3", "m4a", "ogg", "opus"].contains(source.pathExtension.lowercased()) ? source.pathExtension.lowercased() : "m4a"
            let out = destination(source, dir, suffix: "compressed", ext: ext)
            var kbps = o.strength.audioBitrate
            if let targetBytes, info.duration > 0 { kbps = max(32, Int(Double(targetBytes) * 8 / info.duration / 1000 * 0.97)) }
            var opts = await FFmpeg.audioOptions(for: ext)
            if let i = opts.firstIndex(of: "-b:a") { opts[i + 1] = "\(kbps)k" } else { opts += ["-b:a", "\(kbps)k"] }
            try await FFmpeg.run(inputs: [source], options: opts, output: out, duration: info.duration) { _ in }
            return [out]
        default:
            throw ConversionError.unsupported("compress \(category.title)")
        }
    }

    private static func encode(_ image: CGImage, ext: String, quality: Double) throws -> Data {
        let temp = try OutputNaming.temporaryDirectory().appendingPathComponent("q.\(ext)")
        if ext == "webp" {
            let semaphore = DispatchSemaphore(value: 0); var failure: Error?
            Task { do { try await ExternalImageEncoders.encodeWebP(image, to: temp, quality: Int(quality * 100)) } catch { failure = error }; semaphore.signal() }
            semaphore.wait(); if let failure { throw failure }
        } else {
            try ImageIOWriter.write(image, to: temp, ext: ext, quality: quality)
        }
        return try Data(contentsOf: temp)
    }

    // MARK: Metadata

    static func metadata(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL) async throws -> [URL] {
        let category = FormatCatalog.category(of: source)
        let suffix = o.removeMetadata ? "clean" : "tagged"
        switch category {
        case .image:
            var ext = source.pathExtension.lowercased(); if ext == "jpeg" { ext = "jpg" }
            let out = destination(source, dir, suffix: suffix, ext: ext)
            if ext == "webp" || ext == "avif" {
                let image = try await ImageLoader.cgImage(from: source)
                if ext == "webp" { try await ExternalImageEncoders.encodeWebP(image, to: out, quality: 90) } else { try await ExternalImageEncoders.encodeAVIF(image, to: out) }
                return [out]
            }
            if o.removeMetadata {
                // Re-encode pixels only; every property dictionary is dropped.
                let image = try await ImageLoader.cgImage(from: source)
                try ImageIOWriter.write(image, to: out, ext: ext, quality: 0.95)
            } else {
                guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), let type = CGImageSourceGetType(src),
                      let dst = CGImageDestinationCreateWithURL(out as CFURL, type, CGImageSourceGetCount(src), nil) else { throw ConversionError.readFailed(source.lastPathComponent) }
                var props: [CFString: Any] = [:]
                var tiff: [CFString: Any] = [:], iptc: [CFString: Any] = [:]
                if !o.metaAuthor.isEmpty { tiff[kCGImagePropertyTIFFArtist] = o.metaAuthor }
                if !o.metaCopyright.isEmpty { tiff[kCGImagePropertyTIFFCopyright] = o.metaCopyright; iptc[kCGImagePropertyIPTCCopyrightNotice] = o.metaCopyright }
                if !o.metaTitle.isEmpty { tiff[kCGImagePropertyTIFFImageDescription] = o.metaTitle; iptc[kCGImagePropertyIPTCObjectName] = o.metaTitle }
                if !o.metaKeywords.isEmpty { iptc[kCGImagePropertyIPTCKeywords] = o.metaKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                props[kCGImagePropertyTIFFDictionary] = tiff
                props[kCGImagePropertyIPTCDictionary] = iptc
                for i in 0..<CGImageSourceGetCount(src) { CGImageDestinationAddImageFromSource(dst, src, i, props as CFDictionary) }
                guard CGImageDestinationFinalize(dst) else { throw ConversionError.writeFailed(out.lastPathComponent) }
            }
            return [out]
        case .pdf:
            guard let doc = PDFDocument(url: source) else { throw ConversionError.readFailed("PDF") }
            let out = destination(source, dir, suffix: suffix, ext: "pdf")
            var attrs: [AnyHashable: Any] = o.removeMetadata ? [:] : (doc.documentAttributes ?? [:])
            if !o.removeMetadata {
                if !o.metaTitle.isEmpty { attrs[PDFDocumentAttribute.titleAttribute] = o.metaTitle }
                if !o.metaAuthor.isEmpty { attrs[PDFDocumentAttribute.authorAttribute] = o.metaAuthor }
                if !o.metaKeywords.isEmpty { attrs[PDFDocumentAttribute.keywordsAttribute] = o.metaKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            }
            doc.documentAttributes = attrs
            guard doc.write(to: out) else { throw ConversionError.writeFailed("PDF") }
            return [out]
        case .audio, .video:
            let out = destination(source, dir, suffix: suffix)
            var opts = ["-map", "0", "-c", "copy"]
            if o.removeMetadata { opts += ["-map_metadata", "-1", "-map_chapters", "-1"] }
            else {
                if !o.metaTitle.isEmpty { opts += ["-metadata", "title=\(o.metaTitle)"] }
                if !o.metaAuthor.isEmpty { opts += ["-metadata", "artist=\(o.metaAuthor)"] }
                if !o.metaCopyright.isEmpty { opts += ["-metadata", "copyright=\(o.metaCopyright)"] }
            }
            try await FFmpeg.run(input: source, options: opts, output: out) { _ in }
            return [out]
        default:
            throw ConversionError.unsupported("metadata for \(category.title)")
        }
    }

    // MARK: Image tools

    static func adjust(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL) async throws -> [URL] {
        let image = try await ImageLoader.cgImage(from: source)
        var ci = CIImage(cgImage: image)
        if o.exposure != 0 { let f = CIFilter.exposureAdjust(); f.inputImage = ci; f.ev = Float(o.exposure); ci = f.outputImage ?? ci }
        let color = CIFilter.colorControls(); color.inputImage = ci; color.brightness = Float(o.brightness); color.contrast = Float(o.contrast); color.saturation = Float(o.saturation)
        ci = color.outputImage ?? ci
        if o.sharpness > 0 { let f = CIFilter.sharpenLuminance(); f.inputImage = ci; f.sharpness = Float(o.sharpness); ci = f.outputImage ?? ci }
        guard let rendered = CIContext().createCGImage(ci, from: CGRect(x: 0, y: 0, width: image.width, height: image.height)) else { throw ConversionError.writeFailed("Could not render the photo adjustments") }
        let out = destination(source, dir, suffix: "edited", ext: outputExt(source))
        try write(rendered, to: out)
        return [out]
    }

    static func addBackground(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL) async throws -> [URL] {
        let image = try await ImageLoader.cgImage(from: source)
        let pad = CGFloat(o.padding)
        var canvasW = CGFloat(image.width) + pad * 2, canvasH = CGFloat(image.height) + pad * 2
        if let ratio = o.aspect.ratio {
            if canvasW / canvasH < ratio { canvasW = canvasH * ratio } else { canvasH = canvasW / ratio }
        }
        guard canvasW * canvasH < 100_000_000 else { throw ConversionError.invalidOptions("This frame would be too large. Use less padding or a closer output ratio.") }
        guard let ctx = CGContext(data: nil, width: Int(canvasW), height: Int(canvasH), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ConversionError.writeFailed("canvas") }
        ctx.setFillColor(o.backgroundColor)
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        let rect = CGRect(x: (canvasW - CGFloat(image.width)) / 2, y: (canvasH - CGFloat(image.height)) / 2, width: CGFloat(image.width), height: CGFloat(image.height))
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: CGFloat(o.cornerRadius), cornerHeight: CGFloat(o.cornerRadius), transform: nil))
        ctx.clip()
        ctx.draw(image, in: rect)
        ctx.restoreGState()
        guard let result = ctx.makeImage() else { throw ConversionError.writeFailed("background") }
        let out = destination(source, dir, suffix: "framed", ext: "png")
        try ImageIOWriter.write(result, to: out, ext: "png", quality: nil)
        return [out]
    }

    static func crop(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL, _ progress: @escaping (Double) -> Void) async throws -> [URL] {
        let category = FormatCatalog.category(of: source)
        if category == .video {
            let info = await FFmpeg.info(of: source)
            let rect = cropRect(width: info.width, height: info.height, o)
            let ext = source.pathExtension.lowercased()
            let out = destination(source, dir, suffix: "cropped", ext: ext)
            var opts = await ffmpegVideoBase(ext)
            if let i = opts.firstIndex(of: "-vf") { opts.remove(at: i); opts.remove(at: i) }
            opts += ["-vf", "crop=\(Int(rect.width)/2*2):\(Int(rect.height)/2*2):\(Int(rect.minX)):\(Int(rect.minY))"]
            try await FFmpeg.run(inputs: [source], options: opts, output: out, duration: info.duration, progress: progress)
            return [out]
        }
        let image = try await ImageLoader.cgImage(from: source)
        let rect = cropRect(width: image.width, height: image.height, o)
        guard rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else { throw ConversionError.invalidOptions("Keep the crop inside the image.") }
        let out = destination(source, dir, suffix: "cropped", ext: outputExt(source))
        try write(cropped, to: out)
        return [out]
    }

    private static func cropRect(width: Int, height: Int, _ o: ToolOptionsSnapshot) -> CGRect {
        if o.cropAspect == .custom {
            let w = o.cropWidth > 0 ? o.cropWidth : width, h = o.cropHeight > 0 ? o.cropHeight : height
            return CGRect(x: o.cropX, y: o.cropY, width: w, height: h).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let ratio = o.cropAspect.ratio else { return CGRect(x: 0, y: 0, width: width, height: height) }
        var w = CGFloat(width), h = CGFloat(height)
        if w / h > ratio { w = h * ratio } else { h = w / ratio }
        return CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h).integral
    }

    static func redact(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL) async throws -> [URL] {
        let image = try await ImageLoader.cgImage(from: source)
        var boxes: [CGRect] = []
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        var requests: [VNRequest] = []
        if o.redactionKind != .text { requests.append(VNDetectFaceRectanglesRequest()) }
        if o.redactionKind != .faces { let r = VNRecognizeTextRequest(); r.recognitionLevel = .fast; requests.append(r) }
        try handler.perform(requests)
        let size = CGSize(width: image.width, height: image.height)
        for request in requests {
            for case let obs as VNDetectedObjectObservation in request.results ?? [] {
                var rect = VNImageRectForNormalizedRect(obs.boundingBox, Int(size.width), Int(size.height))
                if obs is VNFaceObservation { rect = rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.2) }
                boxes.append(rect)
            }
        }
        guard !boxes.isEmpty else { throw ConversionError.invalidOptions("No \(o.redactionKind == .faces ? "faces" : (o.redactionKind == .text ? "text" : "faces or text")) were detected in this photo.") }
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ConversionError.writeFailed("canvas") }
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        if o.redactionStyle == .solid {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            for box in boxes { ctx.fill(box) }
        } else {
            let blur = CIFilter.gaussianBlur(); blur.inputImage = CIImage(cgImage: image); blur.radius = Float(max(12, Double(max(image.width, image.height)) / 60))
            if let blurred = blur.outputImage, let cg = CIContext().createCGImage(blurred, from: CGRect(origin: .zero, size: size)) {
                for box in boxes {
                    ctx.saveGState(); ctx.clip(to: box)
                    ctx.draw(cg, in: CGRect(origin: .zero, size: size))
                    ctx.restoreGState()
                }
            }
        }
        guard let result = ctx.makeImage() else { throw ConversionError.writeFailed("redacted photo") }
        let out = destination(source, dir, suffix: "redacted", ext: outputExt(source))
        try write(result, to: out)
        return [out]
    }

    static func createPDF(_ files: [URL], _ dir: URL) async throws -> URL {
        let doc = PDFDocument()
        for (i, file) in files.enumerated() {
            let image = try await ImageLoader.cgImage(from: file)
            guard let page = PDFPage(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))) else { continue }
            doc.insert(page, at: i)
        }
        let out = OutputNaming.unique(in: dir, baseName: files[0].deletingPathExtension().lastPathComponent + " combined", ext: "pdf")
        guard doc.write(to: out) else { throw ConversionError.writeFailed("PDF") }
        return out
    }

    static func collage(_ files: [URL], _ o: ToolOptionsSnapshot, _ dir: URL) async throws -> URL {
        var images: [CGImage] = []
        for file in files { images.append(ImageIOWriter.resized(try await ImageLoader.cgImage(from: file), maxDimension: 1600)) }
        let columns = max(1, min(o.columns, images.count))
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let cell = 800.0, spacing = o.spacing
        let width = Double(columns) * cell + Double(columns + 1) * spacing
        let height = Double(rows) * cell + Double(rows + 1) * spacing
        guard let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ConversionError.writeFailed("Could not create the collage canvas") }
        ctx.setFillColor(o.collageBackground)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (i, image) in images.enumerated() {
            let col = i % columns, row = i / columns
            let x = spacing + Double(col) * (cell + spacing)
            let y = height - spacing - Double(row + 1) * cell - Double(row) * spacing
            let scale = min(cell / Double(image.width), cell / Double(image.height))
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            let rect = CGRect(x: x + (cell - w) / 2, y: y + (cell - h) / 2, width: w, height: h)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: o.collageCornerRadius, cornerHeight: o.collageCornerRadius, transform: nil)); ctx.clip()
            ctx.draw(image, in: rect)
            ctx.restoreGState()
        }
        guard let result = ctx.makeImage() else { throw ConversionError.writeFailed("Could not render the collage") }
        let out = OutputNaming.unique(in: dir, baseName: files[0].deletingPathExtension().lastPathComponent + " collage", ext: "png")
        try ImageIOWriter.write(result, to: out, ext: "png", quality: nil)
        return out
    }

    static func rotate(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL) async throws -> [URL] {
        if FormatCatalog.category(of: source) == .pdf {
            guard let doc = PDFDocument(url: source) else { throw ConversionError.readFailed("PDF") }
            for i in 0..<doc.pageCount { doc.page(at: i)?.rotation += o.rotation }
            let out = destination(source, dir, suffix: "rotated", ext: "pdf")
            guard doc.write(to: out) else { throw ConversionError.writeFailed("PDF") }
            return [out]
        }
        let image = try await ImageLoader.cgImage(from: source)
        let turns = ((o.rotation / 90) % 4 + 4) % 4
        let swap = turns % 2 == 1
        let w = swap ? image.height : image.width, h = swap ? image.width : image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ConversionError.writeFailed("canvas") }
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: -CGFloat(turns) * .pi / 2)
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let result = ctx.makeImage() else { throw ConversionError.writeFailed("rotate") }
        let out = destination(source, dir, suffix: "rotated", ext: outputExt(source))
        try write(result, to: out)
        return [out]
    }

    private static func outputExt(_ source: URL) -> String {
        let ext = source.pathExtension.lowercased()
        if ["jpg", "jpeg"].contains(ext) { return "jpg" }
        if ["png", "heic", "tiff", "bmp"].contains(ext) { return ext }
        return "png"
    }

    private static func write(_ image: CGImage, to url: URL) throws {
        try ImageIOWriter.write(image, to: url, ext: url.pathExtension, quality: 0.92)
    }

    // MARK: Media tools

    static func trim(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL, _ progress: @escaping (Double) -> Void) async throws -> [URL] {
        let info = await FFmpeg.info(of: source)
        let end = o.endTime > 0 ? o.endTime : info.duration
        guard o.startTime >= 0, end > o.startTime, end <= info.duration + 0.5 else { throw ConversionError.invalidOptions("Set a start and end within the file.") }
        let ext = source.pathExtension.lowercased()
        let out = destination(source, dir, suffix: "trimmed", ext: ext)
        let opts = ["-ss", "\(o.startTime)", "-to", "\(end)"] + (info.hasVideo ? await ffmpegVideoBase(ext) : await FFmpeg.audioOptions(for: ext))
        try await FFmpeg.run(inputs: [source], options: opts, output: out, duration: end - o.startTime, progress: progress)
        return [out]
    }

    static func split(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL, _ progress: @escaping (Double) -> Void) async throws -> [URL] {
        if FormatCatalog.category(of: source) == .pdf {
            guard let doc = PDFDocument(url: source) else { throw ConversionError.readFailed("PDF") }
            let ranges = o.pageRanges.isEmpty ? (1...max(doc.pageCount, 1)).map { ($0, $0) } : parseRanges(o.pageRanges, max: doc.pageCount)
            guard !ranges.isEmpty else { throw ConversionError.invalidOptions("Enter page ranges like 1-3, 5, 8-10.") }
            var outputs: [URL] = []
            let base = source.deletingPathExtension().lastPathComponent
            for (a, b) in ranges {
                let part = PDFDocument()
                for p in a...b { if let page = doc.page(at: p - 1)?.copy() as? PDFPage { part.insert(page, at: part.pageCount) } }
                let out = OutputNaming.unique(in: dir, baseName: a == b ? "\(base) page \(a)" : "\(base) pages \(a)-\(b)", ext: "pdf")
                guard part.write(to: out) else { throw ConversionError.writeFailed("PDF") }
                outputs.append(out)
            }
            return outputs
        }
        let info = await FFmpeg.info(of: source)
        let points = o.splitPoints.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }).compactMap { parseTime(String($0)) }.sorted()
        guard !points.isEmpty, points.allSatisfy({ $0 > 0.05 && $0 < info.duration - 0.05 }) else { throw ConversionError.invalidOptions("Add split points inside the file, at least 0.05 seconds from either end.") }
        let bounds = [0.0] + points + [info.duration]
        let ext = source.pathExtension.lowercased()
        let codec = info.hasVideo ? await ffmpegVideoBase(ext) : await FFmpeg.audioOptions(for: ext)
        var outputs: [URL] = []
        for i in 0..<(bounds.count - 1) {
            let out = destination(source, dir, suffix: "part \(i + 1)", ext: ext)
            try await FFmpeg.run(inputs: [source], options: ["-ss", "\(bounds[i])", "-to", "\(bounds[i + 1])"] + codec, output: out, duration: bounds[i + 1] - bounds[i]) { p in progress((Double(i) + p) / Double(bounds.count - 1)) }
            outputs.append(out)
        }
        return outputs
    }

    static func merge(_ files: [URL], _ o: ToolOptionsSnapshot, _ dir: URL, _ progress: @escaping (Double) -> Void) async throws -> URL {
        let sorted = o.mergeSorted ? files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } : files
        let category = FormatCatalog.category(of: sorted[0])
        let base = sorted[0].deletingPathExtension().lastPathComponent + " merged"
        if category == .pdf {
            let doc = PDFDocument()
            for file in sorted {
                guard let part = PDFDocument(url: file) else { throw ConversionError.readFailed(file.lastPathComponent) }
                for p in 0..<part.pageCount { if let page = part.page(at: p)?.copy() as? PDFPage { doc.insert(page, at: doc.pageCount) } }
            }
            let out = OutputNaming.unique(in: dir, baseName: base, ext: "pdf")
            guard doc.write(to: out) else { throw ConversionError.writeFailed("PDF") }
            return out
        }
        let infos = await withTaskGroup(of: (Int, FFmpeg.StreamInfo).self) { group -> [FFmpeg.StreamInfo] in
            for (i, f) in sorted.enumerated() { group.addTask { (i, await FFmpeg.info(of: f)) } }
            var result = Array(repeating: FFmpeg.StreamInfo(), count: sorted.count)
            for await (i, info) in group { result[i] = info }
            return result
        }
        let total = infos.reduce(0) { $0 + $1.duration }
        let n = sorted.count
        if category == .video {
            guard infos.allSatisfy(\.hasVideo) else { throw ConversionError.invalidOptions("Every selected file must contain a video track.") }
            let w = infos[0].width / 2 * 2, h = infos[0].height / 2 * 2
            let allAudio = infos.allSatisfy(\.hasAudio)
            var filter = ""
            for i in 0..<n {
                filter += "[\(i):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v\(i)];"
                if allAudio { filter += "[\(i):a]aresample=48000,aformat=channel_layouts=stereo[a\(i)];" }
            }
            filter += (0..<n).map { allAudio ? "[v\($0)][a\($0)]" : "[v\($0)]" }.joined()
            filter += "concat=n=\(n):v=1:a=\(allAudio ? 1 : 0)[v]" + (allAudio ? "[a]" : "")
            let h264 = await FFmpeg.pick(["libx264", "h264_videotoolbox"])
            var opts = ["-filter_complex", filter, "-map", "[v]"] + (allAudio ? ["-map", "[a]", "-c:a", "aac", "-b:a", "192k"] : ["-an"])
            opts += ["-c:v", h264, "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
            if h264 == "libx264" { opts += ["-preset", "medium", "-crf", "23"] }
            let out = OutputNaming.unique(in: dir, baseName: base, ext: "mp4")
            try await FFmpeg.run(inputs: sorted, options: opts, output: out, duration: total, progress: progress)
            return out
        }
        let ext = sorted[0].pathExtension.lowercased()
        let filter = (0..<n).map { "[\($0):a]" }.joined() + "concat=n=\(n):v=0:a=1[a]"
        let out = OutputNaming.unique(in: dir, baseName: base, ext: ext)
        var opts = ["-filter_complex", filter, "-map", "[a]"]
        opts += await FFmpeg.audioOptions(for: ext).filter { $0 != "-vn" }
        try await FFmpeg.run(inputs: sorted, options: opts, output: out, duration: total, progress: progress)
        return out
    }

    static func captureFrame(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL) async throws -> [URL] {
        let out = destination(source, dir, suffix: "frame", ext: "png")
        try await FFmpeg.run(inputs: [source], options: ["-ss", "\(o.snapshotTime)", "-frames:v", "1"], output: out, duration: nil) { _ in }
        return [out]
    }

    static func speed(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL, _ progress: @escaping (Double) -> Void) async throws -> [URL] {
        guard o.speed >= 0.25, o.speed <= 8 else { throw ConversionError.invalidOptions("Choose a speed between 0.25x and 8x.") }
        let info = await FFmpeg.info(of: source)
        let ext = source.pathExtension.lowercased()
        let out = destination(source, dir, suffix: "\(o.speed)x", ext: ext)
        var tempo = o.speed, atempo: [String] = []
        while tempo > 2 { atempo.append("atempo=2"); tempo /= 2 }
        while tempo < 0.5 { atempo.append("atempo=0.5"); tempo *= 2 }
        atempo.append("atempo=\(tempo)")
        var opts: [String]
        if info.hasVideo {
            var filter = "[0:v]setpts=PTS/\(o.speed)[v]"
            if info.hasAudio { filter += ";[0:a]\(atempo.joined(separator: ","))[a]" }
            opts = ["-filter_complex", filter, "-map", "[v]"] + (info.hasAudio ? ["-map", "[a]"] : [])
            opts += await ffmpegVideoBase(ext).filter { $0 != "-vf" && !$0.hasPrefix("scale=") }
        } else {
            opts = ["-af", atempo.joined(separator: ",")] + (await FFmpeg.audioOptions(for: ext))
        }
        try await FFmpeg.run(inputs: [source], options: opts, output: out, duration: info.duration / o.speed, progress: progress)
        return [out]
    }

    static func normalize(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL, _ progress: @escaping (Double) -> Void) async throws -> [URL] {
        let ext = source.pathExtension.lowercased()
        let out = destination(source, dir, suffix: "normalized", ext: ext)
        let opts = ["-af", "loudnorm=I=\(o.loudness):TP=-1.5:LRA=11"] + (await FFmpeg.audioOptions(for: ext))
        try await FFmpeg.run(input: source, options: opts, output: out, progress: progress)
        return [out]
    }

    static func channels(_ source: URL, _ o: ToolOptionsSnapshot, _ dir: URL, _ progress: @escaping (Double) -> Void) async throws -> [URL] {
        let info = await FFmpeg.info(of: source)
        guard info.hasAudio else { throw ConversionError.invalidOptions("This file has no audio track.") }
        let ext = source.pathExtension.lowercased()
        let out = destination(source, dir, suffix: o.channels.title.lowercased(), ext: ext)
        var opts = ["-ac", o.channels == .mono ? "1" : "2"]
        opts += info.hasVideo ? ["-c:v", "copy", "-c:a", "aac", "-b:a", "192k"] : (await FFmpeg.audioOptions(for: ext))
        try await FFmpeg.run(inputs: [source], options: opts, output: out, duration: info.duration, progress: progress)
        return [out]
    }

    static func mute(_ source: URL, _ dir: URL, _ progress: @escaping (Double) -> Void) async throws -> [URL] {
        let out = destination(source, dir, suffix: "muted")
        try await FFmpeg.run(input: source, options: ["-c:v", "copy", "-an"], output: out, progress: progress)
        return [out]
    }

    // MARK: Parsing

    static func parseTime(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains(":") { return Subtitles.time(t) }
        return Double(t)
    }

    static func parseRanges(_ s: String, max: Int) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for part in s.split(separator: ",") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            let bounds = piece.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if bounds.count == 1, bounds[0] >= 1, bounds[0] <= max { result.append((bounds[0], bounds[0])) }
            else if bounds.count == 2, bounds[0] >= 1, bounds[1] <= max, bounds[0] <= bounds[1] { result.append((bounds[0], bounds[1])) }
        }
        return result
    }
}

/// Plain-value copy of `ToolOptions` so background work never touches the observable object.
struct ToolOptionsSnapshot {
    let compressionMode: CompressionMode, strength: CompressionStrength, targetSizeKB: Int, reductionPercent: Int, maxDimension: Int
    let removeMetadata: Bool, metaTitle: String, metaAuthor: String, metaCopyright: String, metaKeywords: String
    let exposure: Double, brightness: Double, contrast: Double, saturation: Double, sharpness: Double
    let backgroundColor: CGColor, padding: Double, cornerRadius: Double, aspect: AspectPreset
    let cropAspect: AspectPreset, cropX: Int, cropY: Int, cropWidth: Int, cropHeight: Int
    let redactionKind: RedactionKind, redactionStyle: RedactionStyle
    let startTime: Double, endTime: Double, splitPoints: String, pageRanges: String, speed: Double, snapshotTime: Double
    let loudness: Double, channels: ChannelLayout, rotation: Int
    let columns: Int, spacing: Double, collageBackground: CGColor, collageCornerRadius: Double, mergeSorted: Bool

    @MainActor init(_ o: ToolOptions) {
        compressionMode = o.compressionMode; strength = o.strength; targetSizeKB = o.targetSizeKB; reductionPercent = o.reductionPercent; maxDimension = o.maxDimension
        removeMetadata = o.removeMetadata; metaTitle = o.metaTitle; metaAuthor = o.metaAuthor; metaCopyright = o.metaCopyright; metaKeywords = o.metaKeywords
        exposure = o.exposure; brightness = o.brightness; contrast = o.contrast; saturation = o.saturation; sharpness = o.sharpness
        backgroundColor = NSColor(o.backgroundColor).cgColor; padding = o.padding; cornerRadius = o.cornerRadius; aspect = o.aspect
        cropAspect = o.cropAspect; cropX = o.cropX; cropY = o.cropY; cropWidth = o.cropWidth; cropHeight = o.cropHeight
        redactionKind = o.redactionKind; redactionStyle = o.redactionStyle
        startTime = o.startTime; endTime = o.endTime; splitPoints = o.splitPoints; pageRanges = o.pageRanges; speed = o.speed; snapshotTime = o.snapshotTime
        loudness = o.loudness; channels = o.channels; rotation = o.rotation
        columns = o.columns; spacing = o.spacing; collageBackground = NSColor(o.collageBackground).cgColor; collageCornerRadius = o.collageCornerRadius; mergeSorted = o.mergeSorted
    }
}

/// Lossless-ish PNG shrink: re-encodes through ImageIO with interlacing off; if
/// `pngquant` is installed, uses it for palette quantization.
enum PNGOptimizer {
    static func quantize(_ image: CGImage, to url: URL) async throws {
        guard let pngquant = ["/opt/homebrew/bin/pngquant", "/usr/local/bin/pngquant"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        try? await ProcessRunner.check(URL(fileURLWithPath: pngquant), ["--force", "--skip-if-larger", "--quality", "70-95", "--output", url.path, url.path])
    }
}
