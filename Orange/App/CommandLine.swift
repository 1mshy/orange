import Foundation
import AppKit

/// Headless mode used by the test script and handy for scripting:
///   Orange.app/Contents/MacOS/Orange --convert <file> <ext> [outputDir]
///   Orange.app/Contents/MacOS/Orange --tool <toolId> <file...> [--out dir]
/// Prints the produced paths, one per line, and exits non-zero on failure.
enum CommandLineMode {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard args.count >= 2, args[1] == "--convert" || args[1] == "--tool" || args[1] == "--list" else { return false }
        if args[1] == "--list" {
            for category in FileCategory.allCases {
                print("\(category.rawValue): \(FormatCatalog.targets(for: category).map { $0.ext.isEmpty ? "extract" : $0.ext }.joined(separator: " "))")
            }
            exit(0)
        }
        // The main thread must keep servicing the main actor (settings, option
        // snapshots), so run the work in a task and park main in dispatchMain().
        Task.detached {
            var status: Int32 = 0
            do {
                if args[1] == "--convert" {
                    guard args.count >= 4 else { throw ConversionError.invalidOptions("usage: --convert <file> <ext> [outputDir]") }
                    let source = URL(fileURLWithPath: args[2])
                    let ext = args[3].lowercased() == "extract" ? "" : args[3].lowercased()
                    let directory = args.count >= 5 ? URL(fileURLWithPath: args[4]) : source.deletingLastPathComponent()
                    let category = FormatCatalog.category(of: source)
                    let all = FormatCatalog.targets(for: category) + FormatCatalog.targets(for: .archive)
                    guard let target = all.first(where: { $0.ext == ext }) ?? (ext.isEmpty ? Formats.extract : nil) else { throw ConversionError.unsupported("\(category.rawValue) → \(args[3])") }
                    let converters = await ConversionEngine.shared.converters
                    guard let converter = converters.first(where: { $0.supports(source: source, category: category, target: target) }) else { throw ConversionError.unsupported("\(category.rawValue) → \(target.name)") }
                    let outputs = try await converter.convert(source: source, target: target, outputDirectory: directory) { _ in }
                    outputs.forEach { print($0.path) }
                } else {
                    var files = Array(args.dropFirst(3)).map { URL(fileURLWithPath: $0) }
                    var directory: URL? = nil
                    if let i = files.firstIndex(where: { $0.lastPathComponent == "--out" }), i + 1 < files.count { directory = files[i + 1]; files.removeSubrange(i...(i + 1)) }
                    guard let tool = Tools.all.first(where: { $0.id == args[2] }), !files.isEmpty else { throw ConversionError.invalidOptions("usage: --tool <toolId> <file...> [--out dir]") }
                    let options = await MainActor.run { ToolOptions() }
                    let outputs = try await ToolRunner.run(tool, files: files, options: options, outputDirectory: directory ?? files[0].deletingLastPathComponent()) { _ in }
                    outputs.forEach { print($0.path) }
                }
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                status = 1
            }
            exit(status)
        }
        dispatchMain()
    }
}
