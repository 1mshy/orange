import Foundation
import AppKit
import CoreText

struct Sheet { var name: String; var rows: [[String]] }
struct Workbook { var sheets: [Sheet] }

/// CSV/TSV, XLSX (OOXML) and ODS reading and writing without third-party code.
enum Spreadsheet {
    static let maxRows = 1_000_000, maxColumns = 16_384

    static func read(_ url: URL) throws -> Workbook {
        switch url.pathExtension.lowercased() {
        case "csv": return Workbook(sheets: [Sheet(name: "Sheet1", rows: parseDelimited(try DocumentIO.readText(url), delimiter: ","))])
        case "tsv": return Workbook(sheets: [Sheet(name: "Sheet1", rows: parseDelimited(try DocumentIO.readText(url), delimiter: "\t"))])
        case "xlsx": return try readXLSX(url)
        case "ods": return try readODS(url)
        default: throw ConversionError.unsupported(url.pathExtension)
        }
    }

    static func write(_ workbook: Workbook, to url: URL, ext: String) throws -> [URL] {
        switch ext {
        case "csv", "tsv":
            let delimiter: Character = ext == "csv" ? "," : "\t"
            if workbook.sheets.count <= 1 {
                try delimited(workbook.sheets.first?.rows ?? [], delimiter: delimiter).write(to: url, atomically: true, encoding: .utf8)
                return [url]
            }
            var outputs: [URL] = []
            let base = url.deletingPathExtension().lastPathComponent
            for sheet in workbook.sheets {
                let safe = sheet.name.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression)
                let target = OutputNaming.unique(in: url.deletingLastPathComponent(), baseName: "\(base) - \(safe)", ext: ext)
                try delimited(sheet.rows, delimiter: delimiter).write(to: target, atomically: true, encoding: .utf8)
                outputs.append(target)
            }
            return outputs
        case "xlsx": try writeXLSX(workbook, to: url); return [url]
        case "ods": try writeODS(workbook, to: url); return [url]
        case "pdf": try writePDF(workbook, to: url); return [url]
        default: throw ConversionError.unsupported(ext)
        }
    }

    // MARK: Delimited

    static func parseDelimited(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? { if let p = pending { pending = nil; return p }; return iterator.next() }
        while let ch = next() {
            if inQuotes {
                if ch == "\"" {
                    if let n = next() { if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n } } else { inQuotes = false }
                } else { field.append(ch) }
            } else if ch == "\"" && field.isEmpty { inQuotes = true }
            else if ch == delimiter { row.append(field); field = "" }
            else if ch == "\n" || ch == "\r" {
                if ch == "\r", let n = next(), n != "\n" { pending = n }
                row.append(field); field = ""; rows.append(row); row = []
            } else { field.append(ch) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    static func delimited(_ rows: [[String]], delimiter: Character) -> String {
        rows.map { row in
            row.map { cell -> String in
                if cell.contains(delimiter) || cell.contains("\"") || cell.contains("\n") || cell.contains("\r") {
                    return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return cell
            }.joined(separator: String(delimiter))
        }.joined(separator: "\n") + "\n"
    }

    // MARK: XLSX

    static func readXLSX(_ url: URL) throws -> Workbook {
        let dir = try Archive.unzip(url)
        let shared = try XLSXSharedStrings.parse(dir.appendingPathComponent("xl/sharedStrings.xml"))
        guard let workbookXML = try? XMLDocument(contentsOf: dir.appendingPathComponent("xl/workbook.xml"), options: []) else { throw ConversionError.readFailed("workbook.xml") }
        var rels: [String: String] = [:]
        if let relsXML = try? XMLDocument(contentsOf: dir.appendingPathComponent("xl/_rels/workbook.xml.rels"), options: []) {
            for case let rel as XMLElement in try relsXML.nodes(forXPath: "//*[local-name()='Relationship']") {
                if let id = rel.attribute(forName: "Id")?.stringValue, let target = rel.attribute(forName: "Target")?.stringValue { rels[id] = target }
            }
        }
        var sheets: [Sheet] = []
        for case let sheet as XMLElement in try workbookXML.nodes(forXPath: "//*[local-name()='sheets']/*[local-name()='sheet']") {
            let name = sheet.attribute(forName: "name")?.stringValue ?? "Sheet\(sheets.count + 1)"
            let rid = sheet.attributes?.first(where: { $0.localName == "id" })?.stringValue ?? ""
            var target = rels[rid] ?? "worksheets/sheet\(sheets.count + 1).xml"
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            let rows = try XLSXSheetParser.parse(dir.appendingPathComponent(target), shared: shared)
            sheets.append(Sheet(name: name, rows: trimmed(rows)))
        }
        guard !sheets.isEmpty else { throw ConversionError.readFailed("no worksheets") }
        return Workbook(sheets: sheets)
    }

    static func columnIndex(_ ref: String) -> Int {
        var index = 0
        for ch in ref.uppercased() where ch.isLetter { index = index * 26 + Int(ch.asciiValue! - 64) }
        return max(index - 1, 0)
    }

    static func columnName(_ index: Int) -> String {
        var n = index + 1, name = ""
        while n > 0 { let r = (n - 1) % 26; name = String(UnicodeScalar(65 + r)!) + name; n = (n - 1) / 26 }
        return name
    }

    static func trimmed(_ rows: [[String]]) -> [[String]] {
        var rows = rows
        while let last = rows.last, last.allSatisfy({ $0.isEmpty }) { rows.removeLast() }
        let width = rows.map { row in (row.lastIndex(where: { !$0.isEmpty }) ?? -1) + 1 }.max() ?? 0
        return rows.map { row in
            var r = Array(row.prefix(width)); while r.count < width { r.append("") }; return r
        }
    }

    static func writeXLSX(_ workbook: Workbook, to url: URL) throws {
        let dir = try OutputNaming.temporaryDirectory()
        let fm = FileManager.default
        for sub in ["_rels", "xl/_rels", "xl/worksheets"] { try fm.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true) }
        var contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        """
        var workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>
        """
        var relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        for (i, sheet) in workbook.sheets.enumerated() {
            let n = i + 1
            contentTypes += "<Override PartName=\"/xl/worksheets/sheet\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>\n"
            workbookXML += "<sheet name=\"\(EPUB.xmlEscape(String(sheet.name.prefix(31))))\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>\n"
            relsXML += "<Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>\n"
            var sheetXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>\n"
            for (r, row) in sheet.rows.enumerated() {
                sheetXML += "<row r=\"\(r + 1)\">"
                for (c, cell) in row.enumerated() where !cell.isEmpty {
                    let ref = "\(columnName(c))\(r + 1)"
                    if let number = Double(cell), !cell.hasPrefix("+"), cell.count < 16, !cell.lowercased().contains("e") || Double(cell) != nil && cell.lowercased().contains("e") {
                        sheetXML += "<c r=\"\(ref)\"><v>\(number)</v></c>"
                    } else {
                        sheetXML += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(EPUB.xmlEscape(cell))</t></is></c>"
                    }
                }
                sheetXML += "</row>\n"
            }
            sheetXML += "</sheetData></worksheet>"
            try sheetXML.write(to: dir.appendingPathComponent("xl/worksheets/sheet\(n).xml"), atomically: true, encoding: .utf8)
        }
        contentTypes += "</Types>"
        workbookXML += "</sheets></workbook>"
        relsXML += "</Relationships>"
        try contentTypes.write(to: dir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try workbookXML.write(to: dir.appendingPathComponent("xl/workbook.xml"), atomically: true, encoding: .utf8)
        try relsXML.write(to: dir.appendingPathComponent("xl/_rels/workbook.xml.rels"), atomically: true, encoding: .utf8)
        let styles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border/></borders><cellStyleXfs count=\"1\"><xf/></cellStyleXfs><cellXfs count=\"1\"><xf xfId=\"0\"/></cellXfs></styleSheet>"
        try styles.write(to: dir.appendingPathComponent("xl/styles.xml"), atomically: true, encoding: .utf8)
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """
        try rootRels.write(to: dir.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
        try Archive.zipContents(directory: dir, to: url)
    }

    // MARK: ODS

    static func readODS(_ url: URL) throws -> Workbook {
        let dir = try Archive.unzip(url)
        guard let content = try? XMLDocument(contentsOf: dir.appendingPathComponent("content.xml"), options: []) else { throw ConversionError.readFailed("content.xml") }
        var sheets: [Sheet] = []
        for case let table as XMLElement in try content.nodes(forXPath: "//*[local-name()='table']") {
            let name = table.attributes?.first(where: { $0.localName == "name" })?.stringValue ?? "Sheet\(sheets.count + 1)"
            var rows: [[String]] = []
            func visitRows(_ element: XMLElement) {
                for case let child as XMLElement in element.children ?? [] {
                    if child.localName == "table-row" {
                        let repeatCount = min(Int(child.attributes?.first(where: { $0.localName == "number-rows-repeated" })?.stringValue ?? "1") ?? 1, 1000)
                        var row: [String] = []
                        for case let cell as XMLElement in child.children ?? [] where cell.localName == "table-cell" || cell.localName == "covered-table-cell" {
                            let colRepeat = min(Int(cell.attributes?.first(where: { $0.localName == "number-columns-repeated" })?.stringValue ?? "1") ?? 1, 1000)
                            var text = (try? cell.nodes(forXPath: ".//*[local-name()='p']"))?.map { $0.stringValue ?? "" }.joined(separator: "\n") ?? ""
                            if text.isEmpty, let value = cell.attributes?.first(where: { $0.localName == "value" })?.stringValue { text = value }
                            row += Array(repeating: text, count: colRepeat)
                        }
                        let isEmpty = row.allSatisfy { $0.isEmpty }
                        rows += Array(repeating: row, count: isEmpty ? 1 : repeatCount)
                    } else if child.localName == "table-rows" || child.localName == "table-row-group" || child.localName == "table-header-rows" {
                        visitRows(child)
                    }
                }
            }
            visitRows(table)
            sheets.append(Sheet(name: name, rows: trimmed(rows)))
        }
        guard !sheets.isEmpty else { throw ConversionError.readFailed("no tables") }
        return Workbook(sheets: sheets)
    }

    static func writeODS(_ workbook: Workbook, to url: URL) throws {
        let dir = try OutputNaming.temporaryDirectory()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try "application/vnd.oasis.opendocument.spreadsheet".write(to: dir.appendingPathComponent("mimetype"), atomically: false, encoding: .ascii)
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
        <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
        <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
        </manifest:manifest>
        """
        try manifest.write(to: dir.appendingPathComponent("META-INF/manifest.xml"), atomically: true, encoding: .utf8)
        var content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2"><office:body><office:spreadsheet>
        """
        for sheet in workbook.sheets {
            content += "<table:table table:name=\"\(EPUB.xmlEscape(sheet.name))\">\n"
            for row in sheet.rows {
                content += "<table:table-row>"
                for cell in row {
                    if let number = Double(cell), cell.count < 16 {
                        content += "<table:table-cell office:value-type=\"float\" office:value=\"\(number)\"><text:p>\(EPUB.xmlEscape(cell))</text:p></table:table-cell>"
                    } else if cell.isEmpty {
                        content += "<table:table-cell/>"
                    } else {
                        content += "<table:table-cell office:value-type=\"string\"><text:p>\(EPUB.xmlEscape(cell))</text:p></table:table-cell>"
                    }
                }
                content += "</table:table-row>\n"
            }
            content += "</table:table>\n"
        }
        content += "</office:spreadsheet></office:body></office:document-content>"
        try content.write(to: dir.appendingPathComponent("content.xml"), atomically: true, encoding: .utf8)
        try Archive.zipEPUBStyle(directory: dir, to: url)
    }

    // MARK: PDF

    static func writePDF(_ workbook: Workbook, to url: URL) throws {
        let pageSize = CGSize(width: 792, height: 612) // landscape Letter
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL), let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw ConversionError.writeFailed("PDF") }
        let font = CTFontCreateWithName("Helvetica" as CFString, 9, nil)
        let bold = CTFontCreateWithName("Helvetica-Bold" as CFString, 10, nil)
        let margin: CGFloat = 36, rowHeight: CGFloat = 16, padding: CGFloat = 4
        for sheet in workbook.sheets {
            let rows = sheet.rows
            let columns = rows.map(\.count).max() ?? 0
            guard columns > 0 else { continue }
            var widths = (0..<columns).map { c -> CGFloat in
                let longest = rows.prefix(500).map { $0.count > c ? $0[c].count : 0 }.max() ?? 0
                return min(max(CGFloat(longest) * 5.2 + padding * 2, 40), 220)
            }
            let available = pageSize.width - margin * 2
            // Group columns into page-wide chunks.
            var chunks: [[Int]] = [[]]; var used: CGFloat = 0
            for c in 0..<columns {
                if used + widths[c] > available && !chunks[chunks.count - 1].isEmpty { chunks.append([]); used = 0 }
                chunks[chunks.count - 1].append(c); used += widths[c]
                if widths[c] > available { widths[c] = available }
            }
            let rowsPerPage = Int((pageSize.height - margin * 2 - 24) / rowHeight)
            for chunk in chunks {
                var start = 0
                while start < rows.count {
                    ctx.beginPDFPage(nil)
                    let title = NSAttributedString(string: sheet.name, attributes: [kCTFontAttributeName as NSAttributedString.Key: bold])
                    let titleLine = CTLineCreateWithAttributedString(title)
                    ctx.textPosition = CGPoint(x: margin, y: pageSize.height - margin)
                    CTLineDraw(titleLine, ctx)
                    var y = pageSize.height - margin - 24
                    for r in start..<min(start + rowsPerPage, rows.count) {
                        var x = margin
                        for c in chunk {
                            let text = rows[r].count > c ? rows[r][c] : ""
                            ctx.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
                            ctx.stroke(CGRect(x: x, y: y - rowHeight, width: widths[c], height: rowHeight), width: 0.5)
                            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text.replacingOccurrences(of: "\n", with: " "), attributes: [kCTFontAttributeName as NSAttributedString.Key: r == 0 ? bold : font]))
                            ctx.saveGState()
                            ctx.clip(to: CGRect(x: x + padding, y: y - rowHeight, width: widths[c] - padding * 2, height: rowHeight))
                            ctx.textPosition = CGPoint(x: x + padding, y: y - rowHeight + 5)
                            CTLineDraw(line, ctx)
                            ctx.restoreGState()
                            x += widths[c]
                        }
                        y -= rowHeight
                    }
                    ctx.endPDFPage()
                    start += rowsPerPage
                }
            }
        }
        ctx.closePDF()
    }
}

final class XLSXSharedStrings: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inSI = false, inT = false
    static func parse(_ url: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path), let parser = XMLParser(contentsOf: url) else { return [] }
        let delegate = XLSXSharedStrings()
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "si" { inSI = true; current = "" } else if name == "t" && inSI { inT = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inT { current += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "t" { inT = false } else if name == "si" { inSI = false; strings.append(current) }
    }
}

final class XLSXSheetParser: NSObject, XMLParserDelegate {
    private var rows: [[String]] = []
    private var row: [String] = []
    private var rowIndex = 0
    private var cellColumn = 0
    private var cellType = ""
    private var value = ""
    private var inValue = false
    private let shared: [String]
    private var failure: ConversionError?
    init(shared: [String]) { self.shared = shared }

    static func parse(_ url: URL, shared: [String]) throws -> [[String]] {
        guard let parser = XMLParser(contentsOf: url) else { throw ConversionError.readFailed(url.lastPathComponent) }
        let delegate = XLSXSheetParser(shared: shared)
        parser.delegate = delegate
        parser.parse()
        if let failure = delegate.failure { throw failure }
        return delegate.rows
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "row":
            let r = (Int(attributes["r"] ?? "") ?? rows.count + 1) - 1
            if r > Spreadsheet.maxRows { failure = .readFailed("too many rows"); parser.abortParsing(); return }
            while rows.count < r { rows.append([]) }
            row = []; rowIndex = r
        case "c":
            if let ref = attributes["r"] { cellColumn = Spreadsheet.columnIndex(ref) } else { cellColumn = row.count }
            cellType = attributes["t"] ?? ""
            value = ""
        case "v", "t": inValue = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inValue { value += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        switch name {
        case "v", "t": inValue = false
        case "c":
            var text = value
            if cellType == "s", let index = Int(value), shared.indices.contains(index) { text = shared[index] }
            else if cellType == "b" { text = value == "1" ? "TRUE" : "FALSE" }
            else if cellType.isEmpty || cellType == "n", let number = Double(value) {
                text = number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
            }
            while row.count < cellColumn { row.append("") }
            if row.count == cellColumn { row.append(text) } else { row[cellColumn] = text }
            value = ""
        case "row":
            if rows.count == rowIndex { rows.append(row) } else { rows[rowIndex] = row }
        default: break
        }
    }
}

struct SpreadsheetConverter: Converter {
    static let outputs: Set<String> = ["xlsx", "ods", "csv", "tsv", "pdf"]

    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool {
        category == .spreadsheet && Self.outputs.contains(target.ext) && ["csv", "tsv", "xlsx", "ods"].contains(source.pathExtension.lowercased())
    }

    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let destination = OutputNaming.destination(for: source, in: outputDirectory, ext: target.ext)
        progress(0.2)
        let workbook = try Spreadsheet.read(source)
        progress(0.6)
        let outputs = try Spreadsheet.write(workbook, to: destination, ext: target.ext)
        progress(1)
        return outputs
    }
}
