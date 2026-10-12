import AppKit
import UniformTypeIdentifiers

/// macOS maps the `.dot` extension to Microsoft Word templates (`com.microsoft.word.dot`),
/// so content-type based dispatch would reject Graphviz files. Decide by extension instead
/// and treat every opened file as a graph.
final class DocumentController: NSDocumentController {
    static let graphType = "org.graphviz.dot"
    private static let graphExtensions: Set<String> = ["dot", "gv"]

    override func typeForContents(of url: URL) throws -> String {
        if Self.graphExtensions.contains(url.pathExtension.lowercased()) {
            return Self.graphType
        }
        return try super.typeForContents(of: url)
    }

    override func documentClass(forType typeName: String) -> AnyClass? {
        GraphDocument.self
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.allowedContentTypes = Self.graphExtensions.compactMap { UTType(filenameExtension: $0) }
            + [UTType(Self.graphType), .plainText].compactMap { $0 }
        return super.runModalOpenPanel(openPanel, forTypes: nil)
    }
}
