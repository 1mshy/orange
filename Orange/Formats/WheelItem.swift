import Foundation

enum WheelMode: String, CaseIterable {
    case convert, tools, actions
    var title: String {
        switch self {
        case .convert: return "Convert formats"
        case .tools: return "File tools"
        case .actions: return "File actions"
        }
    }
}

/// One petal of the wheel.
struct WheelItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case format(FileFormat)
        case tool(FileTool)
        case action(FileAction)
    }
    let kind: Kind
    var id: String {
        switch kind {
        case .format(let f): return "format.\(f.id)"
        case .tool(let t): return "tool.\(t.id)"
        case .action(let a): return "action.\(a.id)"
        }
    }
    var title: String {
        switch kind {
        case .format(let f): return f.name
        case .tool(let t): return t.name
        case .action(let a): return a.name
        }
    }
    var symbol: String {
        switch kind {
        case .format(let f): return f.category.symbol
        case .tool(let t): return t.symbol
        case .action(let a): return a.symbol
        }
    }
    /// Text shown in the wheel's center label while the petal is selected.
    var caption: String {
        switch kind {
        case .format(let f): return f.ext.isEmpty ? "Extract archive" : "Convert to \(f.name)"
        case .tool(let t): return t.name.capitalized
        case .action(let a): return a.name.capitalized
        }
    }
}
