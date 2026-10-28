import Foundation
import AppKit
import PDFKit
import CoreText

/// Reads documents into NSAttributedString and writes them back out, using
/// AppKit's document readers plus small Markdown and EPUB codecs.
enum DocumentIO {
    static func read(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "text", "": return NSAttributedString(string: try readText(url), attributes: [.font: NSFont.systemFont(ofSize: 12)])
        case "md", "markdown": return Markdown.attributedString(from: try readText(url))
        case "docx": return try attributed(url, type: .officeOpenXML)
        case "doc": return try attributed(url, type: .docFormat)
        case "odt": return try attributed(url, type: .openDocument)
        case "rtf": return try attributed(url, type: .rtf)
        case "rtfd": return try attributed(url, type: .rtfd)
        case "html", "htm": return try attributed(url, type: .html)
        case "textclipping": return try readTextClipping(url)
        case "pages": return try readPages(url)
        case "epub": return try EPUB.read(url)
        case "pdf":
            guard let doc = PDFDocument(url: url) else { throw ConversionError.readFailed("PDF") }
            return pdfAttributedString(doc)
        default: throw ConversionError.unsupported(ext)
        }
    }

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        throw ConversionError.readFailed("text encoding")
    }

    private static func attributed(_ url: URL, type: NSAttributedString.DocumentType) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        if type == .html { options[.characterEncoding] = String.Encoding.utf8.rawValue; options[.baseURL] = url.deletingLastPathComponent() }
        do {
            if type == .rtfd {
                guard let wrapper = try? FileWrapper(url: url), let attr = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) else { throw ConversionError.readFailed("RTFD") }
                return attr
            }
            return try NSAttributedString(url: url, options: options, documentAttributes: nil)
        } catch {
            throw ConversionError.readFailed("\(url.lastPathComponent) (\(error.localizedDescription))")
        }
    }

    private static func readTextClipping(_ url: URL) throws -> NSAttributedString {
        guard let plist = NSDictionary(contentsOf: url), let uti = plist["UTI-Data"] as? [String: Any] else { throw ConversionError.readFailed("text clipping") }
        if let rtf = uti["public.rtf"] as? Data, let attr = NSAttributedString(rtf: rtf, documentAttributes: nil) { return attr }
        if let text = uti["public.utf8-plain-text"] as? String { return NSAttributedString(string: text) }
        if let data = uti["public.utf8-plain-text"] as? Data, let text = String(data: data, encoding: .utf8) { return NSAttributedString(string: text) }
        throw ConversionError.readFailed("text clipping")
    }

    /// Pages packages are not readable by AppKit; their QuickLook preview PDF is.
    static func pagesPreviewPDF(_ url: URL) -> URL? {
        let candidates = ["QuickLook/Preview.pdf", "preview.pdf"]
        for c in candidates {
            let p = url.appendingPathComponent(c)
            if FileManager.default.fileExists(atPath: p.path) { return p }
        }
        return nil
    }

    private static func readPages(_ url: URL) throws -> NSAttributedString {
        guard let preview = pagesPreviewPDF(url), let doc = PDFDocument(url: preview) else {
            throw ConversionError.unsupported("Pages documents without a QuickLook preview (save the document in Pages with preview enabled)")
        }
        return pdfAttributedString(doc)
    }

    static func pdfAttributedString(_ doc: PDFDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let attr = page.attributedString { result.append(attr) } else if let s = page.string { result.append(NSAttributedString(string: s)) }
            if i < doc.pageCount - 1 { result.append(NSAttributedString(string: "\n\u{0C}\n")) }
        }
        return result
    }

    // MARK: Writing

    static func write(_ attr: NSAttributedString, to url: URL, ext: String) throws {
        let range = NSRange(location: 0, length: attr.length)
        switch ext {
        case "txt": try attr.string.write(to: url, atomically: true, encoding: .utf8)
        case "md": try Markdown.markdown(from: attr).write(to: url, atomically: true, encoding: .utf8)
        case "docx": try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: url)
        case "rtf": try attr.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]).write(to: url)
        case "rtfd":
            guard let wrapper = attr.rtfdFileWrapper(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) else { throw ConversionError.writeFailed("RTFD") }
            try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        case "html": try htmlData(attr).write(to: url)
        case "epub": try EPUB.write(attr, to: url, title: url.deletingPathExtension().lastPathComponent)
        case "pdf": try PDFRenderer.render(attr, to: url)
        default: throw ConversionError.unsupported(ext)
        }
    }

    static func htmlData(_ attr: NSAttributedString) throws -> Data {
        try attr.data(from: NSRange(location: 0, length: attr.length), documentAttributes: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
            .excludedElements: ["XML", "DOCTYPE"],
        ])
    }
}

/// Paginates an attributed string into a US Letter / A4-sized PDF with CoreText.
enum PDFRenderer {
    static func render(_ attr: NSAttributedString, to url: URL, pageSize: CGSize = CGSize(width: 612, height: 792), margin: CGFloat = 54) throws {
        guard attr.length > 0 else { throw ConversionError.readFailed("empty document") }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.writeFailed(url.lastPathComponent)
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
        let textRect = mediaBox.insetBy(dx: margin, dy: margin)
        var location = 0
        var pages = 0
        while location < attr.length && pages < 5000 {
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            ctx.beginPDFPage(nil)
            ctx.textMatrix = .identity
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
            location += visible.length
            pages += 1
        }
        ctx.closePDF()
    }
}

/// Minimal CommonMark subset: headings, bullets, numbered lists, code fences,
/// paragraphs, and inline bold/italic/code.
enum Markdown {
    static func attributedString(from text: String) -> NSAttributedString {
        let body = NSFont.systemFont(ofSize: 12)
        let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let result = NSMutableAttributedString()
        var inCode = false
        var paragraph = ""
        func flushParagraph() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(inline(trimmed.replacingOccurrences(of: "\n", with: " "), font: body)); result.append(NSAttributedString(string: "\n\n")) }
            paragraph = ""
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine
            if line.hasPrefix("```") { flushParagraph(); inCode.toggle(); continue }
            if inCode { result.append(NSAttributedString(string: line + "\n", attributes: [.font: mono])); continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flushParagraph(); continue }
            if let level = headingLevel(line) {
                flushParagraph()
                let size: CGFloat = [24, 20, 17, 15, 13, 12][level - 1]
                let title = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                result.append(inline(title, font: NSFont.boldSystemFont(ofSize: size)))
                result.append(NSAttributedString(string: "\n\n"))
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                result.append(inline("•\t" + trimmed.dropFirst(2), font: body, indent: true))
                result.append(NSAttributedString(string: "\n"))
                continue
            }
            if let match = trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
                flushParagraph()
                let number = trimmed[..<match.upperBound].trimmingCharacters(in: .whitespaces)
                result.append(inline("\(number)\t" + trimmed[match.upperBound...], font: body, indent: true))
                result.append(NSAttributedString(string: "\n"))
                continue
            }
            if trimmed.hasPrefix("> ") { paragraph += trimmed.dropFirst(2) + "\n"; continue }
            paragraph += line + "\n"
        }
        flushParagraph()
        return result
    }

    private static func headingLevel(_ line: String) -> Int? {
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        guard level >= 1, level <= 6, line.dropFirst(level).first == " " else { return nil }
        return level
    }

    private static func inline(_ text: String, font: NSFont, indent: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        if indent { style.headIndent = 20; style.firstLineHeadIndent = 4; style.tabStops = [NSTextTab(textAlignment: .left, location: 20)] }
        let base: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        let pattern = #"(\*\*|__)(.+?)\1|(\*|_)(.+?)\3|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var cursor = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor { result.append(NSAttributedString(string: ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), attributes: base)) }
            var attrs = base
            if m.range(at: 2).location != NSNotFound {
                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                result.append(NSAttributedString(string: ns.substring(with: m.range(at: 2)), attributes: attrs))
            } else if m.range(at: 4).location != NSNotFound {
                attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                result.append(NSAttributedString(string: ns.substring(with: m.range(at: 4)), attributes: attrs))
            } else if m.range(at: 5).location != NSNotFound {
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                result.append(NSAttributedString(string: ns.substring(with: m.range(at: 5)), attributes: attrs))
            } else if m.range(at: 6).location != NSNotFound {
                attrs[.link] = ns.substring(with: m.range(at: 7))
                result.append(NSAttributedString(string: ns.substring(with: m.range(at: 6)), attributes: attrs))
            }
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length { result.append(NSAttributedString(string: ns.substring(from: cursor), attributes: base)) }
        return result
    }

    static func markdown(from attr: NSAttributedString) -> String {
        var lines: [String] = []
        let text = attr.string as NSString
        var baseSize: CGFloat = 12
        var sizes: [CGFloat: Int] = [:]
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length)) { value, range, _ in
            if let f = value as? NSFont { sizes[f.pointSize, default: 0] += range.length }
        }
        if let common = sizes.max(by: { $0.value < $1.value })?.key { baseSize = common }
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byParagraphs) { _, range, _, _ in
            guard range.length > 0 else { lines.append(""); return }
            var line = ""
            var isHeadingCandidate = true
            var maxSize: CGFloat = 0
            attr.enumerateAttributes(in: range) { attrs, r, _ in
                var piece = text.substring(with: r).replacingOccurrences(of: "\u{0C}", with: "")
                if piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { line += piece; return }
                let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: baseSize)
                let traits = NSFontManager.shared.traits(of: font)
                maxSize = max(maxSize, font.pointSize)
                if font.pointSize <= baseSize + 1 { isHeadingCandidate = false }
                if font.isFixedPitch { piece = "`\(piece)`" }
                else {
                    let bold = traits.contains(.boldFontMask), italic = traits.contains(.italicFontMask)
                    let lead = piece.prefix(while: { $0 == " " }), trail = piece.reversed().prefix(while: { $0 == " " })
                    let core = piece.trimmingCharacters(in: .whitespaces)
                    if !core.isEmpty {
                        var wrapped = core
                        if bold && italic { wrapped = "***\(core)***" } else if bold { wrapped = "**\(core)**" } else if italic { wrapped = "*\(core)*" }
                        if let link = attrs[.link] { wrapped = "[\(wrapped)](\(link))" }
                        piece = lead + wrapped + trail
                    }
                }
                line += piece
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { lines.append(""); return }
            if isHeadingCandidate && maxSize > baseSize + 1 && trimmed.count < 120 {
                let level = maxSize >= baseSize * 1.8 ? 1 : (maxSize >= baseSize * 1.4 ? 2 : 3)
                let clean = trimmed.replacingOccurrences(of: "**", with: "")
                lines.append(String(repeating: "#", count: level) + " " + clean)
                lines.append("")
            } else if trimmed.hasPrefix("•") || trimmed.hasPrefix("◦") || trimmed.hasPrefix("▪") {
                lines.append("- " + trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
            } else {
                lines.append(trimmed)
                lines.append("")
            }
        }
        var out = lines.joined(separator: "\n")
        while out.contains("\n\n\n") { out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
