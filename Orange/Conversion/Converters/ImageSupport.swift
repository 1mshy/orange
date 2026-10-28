import Foundation
import ImageIO
import AppKit
import UniformTypeIdentifiers

enum ImageLoader {
    /// Decodes the first frame with EXIF orientation applied. Falls back to
    /// NSImage (SVG, PDF) and then to ffmpeg for formats ImageIO cannot read.
    static func cgImage(from url: URL) async throws -> CGImage {
        if let image = imageIO(url) { return image }
        if let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { return cg }
        // ffmpeg fallback (AVIF/HEIF variants, RAW previews).
        if let ffmpeg = ToolLocator.url(for: .ffmpeg) {
            let temp = try OutputNaming.temporaryDirectory().appendingPathComponent("decoded.png")
            try await ProcessRunner.check(ffmpeg, ["-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", url.path, "-frames:v", "1", temp.path])
            if let image = imageIO(temp) { return image }
        }
        throw ConversionError.readFailed(url.lastPathComponent)
    }

    static func imageIO(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func isAnimated(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }
}

enum ImageIOWriter {
    static func utType(forExtension ext: String) -> UTType? {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "heic": return .heic
        case "tiff", "tif": return .tiff
        case "bmp": return .bmp
        case "gif": return .gif
        case "avif": return UTType("public.avif")
        case "webp": return .webP
        default: return UTType(filenameExtension: ext)
        }
    }

    /// Writes with ImageIO. `quality` applies to lossy formats. Metadata is
    /// dropped unless `properties` is supplied.
    static func write(_ image: CGImage, to url: URL, ext: String, quality: Double? = 0.9, properties: [CFString: Any] = [:]) throws {
        guard let type = utType(forExtension: ext) else { throw ConversionError.unsupported(ext) }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.writeFailed("ImageIO cannot encode \(ext.uppercased())")
        }
        var props = properties
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        var toWrite = image
        if ["jpg", "jpeg", "bmp"].contains(ext.lowercased()), image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst {
            toWrite = flattened(image)
        }
        CGImageDestinationAddImage(destination, toWrite, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.writeFailed("ImageIO could not finish \(url.lastPathComponent)") }
    }

    /// Composites an image with alpha onto white.
    static func flattened(_ image: CGImage, background: CGColor = CGColor(gray: 1, alpha: 1)) -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func resized(_ image: CGImage, maxDimension: Int) -> CGImage {
        let scale = min(1, CGFloat(maxDimension) / CGFloat(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let w = max(1, Int(CGFloat(image.width) * scale)), h = max(1, Int(CGFloat(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func pngData(_ image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw ConversionError.writeFailed("PNG") }
        return data
    }
}

/// WebP and AVIF encoders: ImageIO where available, else cwebp / ffmpeg.
enum ExternalImageEncoders {
    static func encodeWebP(_ image: CGImage, to url: URL, quality: Int = 85, lossless: Bool = false) async throws {
        let temp = try OutputNaming.temporaryDirectory().appendingPathComponent("source.png")
        try ImageIOWriter.write(image, to: temp, ext: "png", quality: nil)
        if let cwebp = ToolLocator.url(for: .cwebp) {
            var args = ["-quiet", "-metadata", "none"]
            args += lossless ? ["-lossless"] : ["-q", "\(quality)"]
            args += [temp.path, "-o", url.path]
            try await ProcessRunner.check(cwebp, args)
            return
        }
        if let ffmpeg = ToolLocator.url(for: .ffmpeg) {
            var args = ["-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", temp.path, "-c:v", "libwebp"]
            args += lossless ? ["-lossless", "1"] : ["-quality", "\(quality)"]
            args += [url.path]
            try await ProcessRunner.check(ffmpeg, args)
            return
        }
        throw ConversionError.toolMissing("cwebp")
    }

    static func encodeAVIF(_ image: CGImage, to url: URL, quality: Double = 0.75) async throws {
        if let type = UTType("public.avif"), let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination) { return }
        }
        let ffmpeg = try ToolLocator.require(.ffmpeg)
        let temp = try OutputNaming.temporaryDirectory().appendingPathComponent("source.png")
        try ImageIOWriter.write(ImageIOWriter.flattened(image), to: temp, ext: "png", quality: nil)
        let crf = Int((1 - quality) * 50) + 10
        let encoder = await FFmpeg.hasEncoder("libaom-av1") ? "libaom-av1" : (await FFmpeg.hasEncoder("libsvtav1") ? "libsvtav1" : "libaom-av1")
        var args = ["-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", temp.path, "-c:v", encoder, "-pix_fmt", "yuv420p", "-crf", "\(crf)"]
        if encoder == "libaom-av1" { args += ["-still-picture", "1", "-cpu-used", "6"] }
        args += ["-frames:v", "1", url.path]
        try await ProcessRunner.check(ffmpeg, args)
    }
}
