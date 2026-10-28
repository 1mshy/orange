import Foundation
import AppKit

/// EPUB reading (container → package → spine → XHTML) and a minimal EPUB 3 writer.
enum EPUB {
    static func read(_ url: URL) throws -> NSAttributedString {
        let dir = try Archive.unzip(url)
        let containerURL = dir.appendingPathComponent("META-INF/container.xml")
        guard let container = try? XMLDocument(contentsOf: containerURL, options: []),
              let rootfile = try container.nodes(forXPath: "//*[local-name()='rootfile']").first as? XMLElement,
              let opfPath = rootfile.attribute(forName: "full-path")?.stringValue else {
            throw ConversionError.readFailed("EPUB container document")
        }
        let opfURL = dir.appendingPathComponent(opfPath)
        guard let opf = try? XMLDocument(contentsOf: opfURL, options: []) else { throw ConversionError.readFailed("EPUB package document") }
        var manifest: [String: String] = [:]
        for case let item as XMLElement in try opf.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']") {
            if let id = item.attribute(forName: "id")?.stringValue, let href = item.attribute(forName: "href")?.stringValue { manifest[id] = href }
        }
        var chapters: [URL] = []
        for case let ref as XMLElement in try opf.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']") {
            if let idref = ref.attribute(forName: "idref")?.stringValue, let href = manifest[idref] {
                chapters.append(opfURL.deletingLastPathComponent().appendingPathComponent(href.removingPercentEncoding ?? href))
            }
        }
        guard !chapters.isEmpty else { throw ConversionError.readFailed("EPUB has no readable chapters") }
        let result = NSMutableAttributedString()
        for chapter in chapters {
            guard let data = try? Data(contentsOf: chapter) else { continue }
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
                .baseURL: chapter.deletingLastPathComponent(),
            ]
            if let attr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                result.append(attr)
                result.append(NSAttributedString(string: "\n\n"))
            }
        }
        guard result.length > 0 else { throw ConversionError.readFailed("EPUB chapters") }
        return result
    }

    static func write(_ attr: NSAttributedString, to url: URL, title: String) throws {
        let dir = try OutputNaming.temporaryDirectory()
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("OEBPS"), withIntermediateDirectories: true)
        try "application/epub+zip".write(to: dir.appendingPathComponent("mimetype"), atomically: false, encoding: .ascii)
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """
        try container.write(to: dir.appendingPathComponent("META-INF/container.xml"), atomically: true, encoding: .utf8)

        // Body HTML from AppKit, then wrapped in XHTML.
        var html = String(decoding: try DocumentIO.htmlData(attr), as: UTF8.self)
        if let bodyStart = html.range(of: "<body"), let bodyOpenEnd = html[bodyStart.upperBound...].firstIndex(of: ">"), let bodyEnd = html.range(of: "</body>") {
            html = String(html[html.index(after: bodyOpenEnd)..<bodyEnd.lowerBound])
        }
        html = html.replacingOccurrences(of: "<br>", with: "<br/>").replacingOccurrences(of: "&nbsp;", with: "&#160;")
        let escapedTitle = xmlEscape(title)
        let chapter = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>\(escapedTitle)</title><meta charset="utf-8"/></head>
        <body>\(html)</body></html>
        """
        try chapter.write(to: dir.appendingPathComponent("OEBPS/chapter1.xhtml"), atomically: true, encoding: .utf8)
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>Contents</title></head>
        <body><nav epub:type="toc" id="toc"><h1>Contents</h1><ol><li><a href="chapter1.xhtml">\(escapedTitle)</a></li></ol></nav></body></html>
        """
        try nav.write(to: dir.appendingPathComponent("OEBPS/nav.xhtml"), atomically: true, encoding: .utf8)
        let uuid = UUID().uuidString
        let modified = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ".\\d+", with: "", options: .regularExpression)
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:uuid:\(uuid)</dc:identifier>
            <dc:title>\(escapedTitle)</dc:title>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="chapter1"/></spine>
        </package>
        """
        try opf.write(to: dir.appendingPathComponent("OEBPS/content.opf"), atomically: true, encoding: .utf8)
        try Archive.zipEPUBStyle(directory: dir, to: url)
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Zip helpers built on the system `zip`/`unzip`/`ditto` binaries.
enum Archive {
    static func unzip(_ url: URL) throws -> URL {
        let dir = try OutputNaming.temporaryDirectory()
        let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        Task {
            do { try await ProcessRunner.check(unzip, ["-q", "-o", url.path, "-d", dir.path]) } catch { failure = error }
            semaphore.signal()
        }
        semaphore.wait()
        if let failure { throw failure }
        return dir
    }

    /// Zips a directory's contents with `mimetype` stored first and uncompressed (EPUB/ODS rule).
    static func zipEPUBStyle(directory: URL, to url: URL) throws {
        let zip = URL(fileURLWithPath: "/usr/bin/zip")
        try? FileManager.default.removeItem(at: url)
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        Task {
            do {
                try await ProcessRunner.check(zip, ["-X", "-0", url.path, "mimetype"], currentDirectory: directory)
                let others = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0 != "mimetype" }
                try await ProcessRunner.check(zip, ["-X", "-r", url.path] + others, currentDirectory: directory)
            } catch { failure = error }
            semaphore.signal()
        }
        semaphore.wait()
        if let failure { throw failure }
    }

    static func zipContents(directory: URL, to url: URL) throws {
        let zip = URL(fileURLWithPath: "/usr/bin/zip")
        try? FileManager.default.removeItem(at: url)
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        Task {
            do { try await ProcessRunner.check(zip, ["-X", "-r", url.path, "."], currentDirectory: directory) } catch { failure = error }
            semaphore.signal()
        }
        semaphore.wait()
        if let failure { throw failure }
    }
}
