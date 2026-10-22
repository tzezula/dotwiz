import AppKit
import PDFKit
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "com.tzezula.dotwiz", category: "render")

/// Shows the rendered graph for one document and re-renders it when the file changes.
final class GraphWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let pdfView = PDFView()
    private let statusBar = StatusBar()
    private var watcher: FileWatcher?
    private var currentJob: RenderJob?
    private var hasRenderedOnce = false

    private static let exportResolutionKey = "ExportResolution"

    private var graphDocument: GraphDocument? { document as? GraphDocument }
    private var sourceURL: URL? { graphDocument?.sourceURL }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.minSize = NSSize(width: 320, height: 240)
        window.titlebarSeparatorStyle = .line
        window.tabbingMode = .preferred
        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true
        buildContent(in: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildContent(in window: NSWindow) {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displaysPageBreaks = false
        pdfView.pageShadowsEnabled = false
        pdfView.backgroundColor = .textBackgroundColor
        pdfView.translatesAutoresizingMaskIntoConstraints = false

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.isHidden = true

        let stack = NSStackView(views: [pdfView, statusBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fill
        pdfView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        statusBar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        pdfView.setContentHuggingPriority(.defaultLow, for: .vertical)
        statusBar.setContentHuggingPriority(.required, for: .vertical)

        window.contentView = stack
        window.initialFirstResponder = pdfView
    }

    /// The graph currently on screen, or nil if nothing has rendered successfully yet.
    var renderedGraph: PDFDocument? {
        hasRenderedOnce ? pdfView.document : nil
    }

    override var document: AnyObject? {
        didSet {
            startWatching()
        }
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        displayName
    }

    func windowWillClose(_ notification: Notification) {
        watcher?.stop()
        watcher = nil
        currentJob?.cancel()
        currentJob = nil
    }

    // MARK: - Watching and rendering

    private func startWatching() {
        watcher?.stop()
        guard let url = sourceURL else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            log.info("File changed: \(url.path, privacy: .public)")
            self?.render()
        }
        watcher?.start()
        render()
    }

    private func render() {
        guard let url = sourceURL, let document = graphDocument else { return }
        currentJob?.cancel()
        window?.subtitle = "Rendering…"

        currentJob = Graphviz.render(fileURL: url, format: "pdf", engine: document.layoutEngine) { [weak self] result in
            guard let self else { return }
            self.currentJob = nil
            switch result {
            case .success(let output):
                self.apply(output)
            case .failure(let error):
                self.window?.subtitle = "Failed"
                self.statusBar.show(error.localizedDescription, severity: .error)
            }
        }
    }

    private func apply(_ result: RenderResult) {
        if result.exitStatus == 0 && result.output.isEmpty {
            // Typically a file caught mid-write (truncated); a follow-up change event
            // will trigger another render.
            window?.subtitle = "Waiting for file…"
            return
        }
        guard result.succeeded, let pdf = PDFDocument(data: result.output) else {
            log.info("Render failed: \(result.diagnostics, privacy: .public)")
            window?.subtitle = hasRenderedOnce ? "Error — showing last good render" : "Error"
            let message = result.diagnostics.isEmpty
                ? "Graphviz exited with status \(result.exitStatus)."
                : result.diagnostics
            statusBar.show(message, severity: .error)
            return
        }

        display(pdf)
        hasRenderedOnce = true
        log.info("Rendered \(self.sourceURL?.path ?? "", privacy: .public) (\(result.output.count) bytes)")
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        window?.subtitle = "Updated \(time)"
        if result.diagnostics.isEmpty {
            statusBar.hide()
        } else {
            statusBar.show(result.diagnostics, severity: .warning)
        }
    }

    /// Swaps in a new rendering while keeping the user's zoom level and scroll position.
    private func display(_ pdf: PDFDocument) {
        guard hasRenderedOnce, !pdfView.autoScales else {
            pdfView.document = pdf
            pdfView.autoScales = true
            return
        }
        let scale = pdfView.scaleFactor
        let clipView = pdfView.documentView?.enclosingScrollView?.contentView
        let origin = clipView?.bounds.origin

        pdfView.document = pdf
        pdfView.scaleFactor = scale
        pdfView.layoutDocumentView()
        if let clipView, let origin {
            clipView.scroll(to: origin)
            clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
        }
    }

    // MARK: - Actions

    @objc func reloadGraph(_ sender: Any?) {
        render()
    }

    @objc func zoomToFit(_ sender: Any?) {
        pdfView.autoScales = true
    }

    @objc func zoomToActualSize(_ sender: Any?) {
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.0
    }

    @objc func zoomInGraph(_ sender: Any?) {
        pdfView.autoScales = false
        pdfView.zoomIn(sender)
    }

    @objc func zoomOutGraph(_ sender: Any?) {
        pdfView.autoScales = false
        pdfView.zoomOut(sender)
    }

    @objc func selectLayoutEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = LayoutEngine(rawValue: raw),
              let document = graphDocument else { return }
        document.layoutEngine = engine
        UserDefaults.standard.set(engine.rawValue, forKey: GraphDocument.defaultsEngineKey)
        render()
    }

    @objc func revealSourceInFinder(_ sender: Any?) {
        guard let url = sourceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func exportGraph(_ sender: Any?) {
        guard let window, let url = sourceURL, let document = graphDocument else { return }
        let initial = ((sender as? NSMenuItem)?.representedObject as? String).flatMap(ExportFormat.init) ?? .png
        let formats = ExportFormat.allCases
        let resolutions = ExportResolution.allCases
        let defaults = UserDefaults.standard
        let savedResolution = ExportResolution(rawValue: defaults.integer(forKey: Self.exportResolutionKey)) ?? .retina

        let panel = NSSavePanel()
        panel.title = "Export as \(initial.title)"
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent
        panel.allowedContentTypes = [initial.contentType]
        panel.isExtensionHidden = false

        let formatPopup = NSPopUpButton()
        formatPopup.addItems(withTitles: formats.map(\.title))
        formatPopup.selectItem(at: formats.firstIndex(of: initial) ?? 0)
        let resolutionPopup = NSPopUpButton()
        resolutionPopup.addItems(withTitles: resolutions.map(\.title))
        resolutionPopup.selectItem(at: resolutions.firstIndex(of: savedResolution) ?? 0)
        resolutionPopup.isEnabled = initial.isRaster

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Format:"), formatPopup],
            [NSTextField(labelWithString: "Resolution:"), resolutionPopup],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        let accessory = NSStackView(views: [grid])
        accessory.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        panel.accessoryView = accessory

        let selectionHandler = PopupHandler { [weak panel, weak resolutionPopup] index in
            let format = formats[index]
            panel?.allowedContentTypes = [format.contentType]
            panel?.title = "Export as \(format.title)"
            resolutionPopup?.isEnabled = format.isRaster
        }
        formatPopup.target = selectionHandler
        formatPopup.action = #selector(PopupHandler.selectionChanged(_:))

        panel.beginSheetModal(for: window) { [weak self] response in
            withExtendedLifetime(selectionHandler) {}
            guard response == .OK, let destination = panel.url else { return }
            let format = formats[formatPopup.indexOfSelectedItem]
            var arguments: [String] = []
            if format.isRaster {
                let resolution = resolutions[resolutionPopup.indexOfSelectedItem]
                defaults.set(resolution.rawValue, forKey: Self.exportResolutionKey)
                arguments.append("-Gdpi=\(resolution.rawValue)")
            }
            Graphviz.render(
                fileURL: url,
                format: format.graphvizFormat,
                engine: document.layoutEngine,
                extraArguments: arguments
            ) { result in
                do {
                    let output = try result.get()
                    guard output.succeeded else {
                        throw NSError(domain: "DotWiz", code: Int(output.exitStatus), userInfo: [
                            NSLocalizedDescriptionKey: "Export failed.",
                            NSLocalizedRecoverySuggestionErrorKey: output.diagnostics,
                        ])
                    }
                    try output.output.write(to: destination, options: .atomic)
                } catch {
                    self?.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
                }
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(exportGraph(_:)) {
            return sourceURL != nil
        }
        if menuItem.action == #selector(selectLayoutEngine(_:)) {
            let selected = graphDocument?.layoutEngine.rawValue
            menuItem.state = (menuItem.representedObject as? String) == selected ? .on : .off
        }
        return true
    }
}

private final class PopupHandler: NSObject {
    private let handler: (Int) -> Void

    init(_ handler: @escaping (Int) -> Void) {
        self.handler = handler
    }

    @objc func selectionChanged(_ sender: NSPopUpButton) {
        handler(sender.indexOfSelectedItem)
    }
}

/// Bar under the graph that shows Graphviz errors and warnings.
private final class StatusBar: NSView {
    enum Severity {
        case warning, error
    }

    private let icon = NSImageView()
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private var heightConstraint: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(separator)
        addSubview(icon)
        addSubview(scrollView)
        heightConstraint = heightAnchor.constraint(equalToConstant: 40)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            icon.widthAnchor.constraint(equalToConstant: 18),
            scrollView.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            heightConstraint,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ message: String, severity: Severity) {
        let color: NSColor = severity == .error ? .systemRed : .systemOrange
        let symbol = severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
        textView.string = message

        // Size to the message, up to a handful of lines; longer output scrolls.
        let lineHeight = (textView.font.map { NSLayoutManager().defaultLineHeight(for: $0) } ?? 14)
        let lines = max(1, min(8, message.split(separator: "\n", omittingEmptySubsequences: false).count))
        heightConstraint.constant = CGFloat(lines) * lineHeight + 16
        isHidden = false
    }

    func hide() {
        isHidden = true
        textView.string = ""
    }
}
