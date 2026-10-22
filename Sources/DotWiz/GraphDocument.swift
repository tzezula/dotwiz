import AppKit
import PDFKit

/// A read-only document backed by a `.dot` file. The file itself is never written; the
/// window controller re-renders it whenever it changes on disk.
@objc(GraphDocument)
final class GraphDocument: NSDocument {
    static let defaultsEngineKey = "LayoutEngine"

    /// Path the document was opened from. Kept separately from `fileURL` because
    /// NSDocument may follow the original inode when an editor renames it to a backup.
    private(set) var sourceURL: URL?

    var layoutEngine: LayoutEngine = {
        let stored = UserDefaults.standard.string(forKey: GraphDocument.defaultsEngineKey) ?? ""
        return LayoutEngine(rawValue: stored) ?? .automatic
    }()

    override class var autosavesInPlace: Bool { false }

    override func read(from url: URL, ofType typeName: String) throws {
        // Fail early with a proper error if the file is unreadable; the content itself is
        // handed to Graphviz by path.
        _ = try FileHandle(forReadingFrom: url).close()
        sourceURL = url
    }

    override func makeWindowControllers() {
        addWindowController(GraphWindowController())
    }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    // Never prompt to save: the document is only a viewer.
    override var isDocumentEdited: Bool { false }

    // MARK: - Printing

    private var renderedGraph: PDFDocument? {
        windowControllers.lazy.compactMap { ($0 as? GraphWindowController)?.renderedGraph }.first
    }

    /// Prints the graph as currently shown, scaled to fit the page and rotated to match its
    /// orientation.
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let graph = renderedGraph else {
            throw CocoaError(.featureUnsupported, userInfo: [
                NSLocalizedDescriptionKey: "There is no rendered graph to print.",
            ])
        }
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        guard let operation = graph.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else {
            throw CocoaError(.featureUnsupported)
        }
        operation.jobTitle = displayName
        return operation
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(printDocument(_:)):
            return renderedGraph != nil
        case #selector(save(_:)), #selector(saveAs(_:)), #selector(revertToSaved(_:)), #selector(duplicate(_:)):
            return false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
