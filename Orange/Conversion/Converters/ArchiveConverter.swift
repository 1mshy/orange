import Foundation

/// ZIP/TAR/GZIP creation and extraction with the system tools; RAR via `unar`.
struct ArchiveConverter: Converter {
    func supports(source: URL, category: FileCategory, target: FileFormat) -> Bool {
        if target.ext.isEmpty { return category == .archive }
        return ["zip", "tar", "gz"].contains(target.ext)
    }

    func convert(source: URL, target: FileFormat, outputDirectory: URL, progress: @escaping (Double) -> Void) async throws -> [URL] {
        let category = FormatCatalog.category(of: source)
        if target.ext.isEmpty { return [try await extract(source, into: outputDirectory)] }
        if category == .archive {
            // Archive → archive: extract to a temp folder, then re-pack its contents.
            let extracted = try await extract(source, into: try OutputNaming.temporaryDirectory())
            progress(0.5)
            let contents = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
            let root = contents.count == 1 ? contents[0] : extracted
            let base = source.deletingPathExtension().lastPathComponent.replacingOccurrences(of: ".tar", with: "")
            return [try await pack(root, baseName: base, ext: target.ext, into: outputDirectory)]
        }
        return [try await pack(source, baseName: source.deletingPathExtension().lastPathComponent, ext: target.ext, into: outputDirectory)]
    }

    private func pack(_ item: URL, baseName: String, ext: String, into directory: URL) async throws -> URL {
        let parent = item.deletingLastPathComponent()
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
        switch ext {
        case "zip":
            let destination = OutputNaming.unique(in: directory, baseName: baseName, ext: "zip")
            try await ProcessRunner.check(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--sequesterRsrc", "--keepParent", item.path, destination.path])
            return destination
        case "tar":
            let destination = OutputNaming.unique(in: directory, baseName: baseName, ext: "tar")
            try await ProcessRunner.check(URL(fileURLWithPath: "/usr/bin/tar"), ["-cf", destination.path, "-C", parent.path, item.lastPathComponent])
            return destination
        default: // gz
            if isDir.boolValue {
                let destination = OutputNaming.unique(in: directory, baseName: baseName, ext: "tar.gz")
                try await ProcessRunner.check(URL(fileURLWithPath: "/usr/bin/tar"), ["-czf", destination.path, "-C", parent.path, item.lastPathComponent])
                return destination
            }
            let destination = OutputNaming.unique(in: directory, baseName: item.lastPathComponent, ext: "gz")
            let result = try await ProcessRunner.check(URL(fileURLWithPath: "/usr/bin/gzip"), ["-c", "-9", item.path])
            try result.stdout.write(to: destination)
            return destination
        }
    }

    private func extract(_ archive: URL, into directory: URL) async throws -> URL {
        let name = archive.lastPathComponent
        let lower = name.lowercased()
        var base = archive.deletingPathExtension().lastPathComponent
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tar.xz") { base = URL(fileURLWithPath: base).deletingPathExtension().lastPathComponent }
        let destination = OutputNaming.unique(in: directory, baseName: base, ext: "")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if lower.hasSuffix(".zip") {
            try await ProcessRunner.check(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, destination.path])
        } else if lower.hasSuffix(".tar") || lower.hasSuffix(".tgz") || lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tar.xz") || lower.hasSuffix(".tbz") {
            try await ProcessRunner.check(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", archive.path, "-C", destination.path])
        } else if lower.hasSuffix(".gz") || lower.hasSuffix(".bz2") || lower.hasSuffix(".xz") {
            try? FileManager.default.removeItem(at: destination)
            let tool = lower.hasSuffix(".gz") ? "/usr/bin/gunzip" : (lower.hasSuffix(".bz2") ? "/usr/bin/bunzip2" : "/usr/bin/xz")
            let args = lower.hasSuffix(".xz") ? ["-d", "-c", archive.path] : ["-c", archive.path]
            let result = try await ProcessRunner.check(URL(fileURLWithPath: tool), args)
            let file = OutputNaming.unique(in: directory, baseName: base, ext: "")
            try result.stdout.write(to: file)
            return file
        } else if lower.hasSuffix(".rar") || lower.hasSuffix(".7z") {
            let unar = try ToolLocator.require(.unar)
            try await ProcessRunner.check(unar, ["-quiet", "-force-overwrite", "-output-directory", destination.path, archive.path])
        } else {
            throw ConversionError.unsupported(archive.pathExtension)
        }
        return destination
    }
}
