import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable {
    case png, jpeg, pdf, svg

    var title: String {
        rawValue.uppercased()
    }

    /// Graphviz `-T` output format.
    var graphvizFormat: String {
        self == .jpeg ? "jpg" : rawValue
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .pdf: return .pdf
        case .svg: return .svg
        }
    }

    /// Bitmap formats depend on the output resolution; vector formats do not.
    var isRaster: Bool {
        self == .png || self == .jpeg
    }
}

enum ExportResolution: Int, CaseIterable {
    case standard = 96
    case retina = 192
    case print = 300

    var title: String {
        switch self {
        case .standard: return "96 dpi (Graphviz default)"
        case .retina: return "192 dpi (2×)"
        case .print: return "300 dpi (print)"
        }
    }
}
