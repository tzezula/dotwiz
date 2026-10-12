import Foundation

enum LayoutEngine: String, CaseIterable {
    /// Let the graph's own `layout` attribute decide (defaults to dot).
    case automatic
    case dot, neato, fdp, sfdp, circo, twopi, osage, patchwork

    var title: String {
        self == .automatic ? "Automatic" : rawValue
    }
}

struct RenderResult {
    let output: Data
    let diagnostics: String
    let exitStatus: Int32

    var succeeded: Bool { exitStatus == 0 && !output.isEmpty }
}

enum GraphvizError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Graphviz 'dot' executable was not found. Install it with 'brew install graphviz', "
                + "or set its path with: defaults write \(Bundle.main.bundleIdentifier ?? "DotWiz") DotPath /path/to/dot"
        }
    }
}

/// A running `dot` invocation that can be cancelled when superseded by a newer render.
final class RenderJob {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    fileprivate init() {}

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        if process.isRunning {
            process.terminate()
        }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    fileprivate func run(executable: URL, arguments: [String], workingDirectory: URL) throws -> RenderResult {
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        try process.run()
        if isCancelled {
            process.terminate()
        }

        // Drain both pipes concurrently so a chatty stderr cannot deadlock the process.
        var diagnostics = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            diagnostics = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return RenderResult(
            output: output,
            diagnostics: String(decoding: diagnostics, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            exitStatus: process.terminationStatus
        )
    }
}

enum Graphviz {
    private static let renderQueue = DispatchQueue(label: "DotWiz.render", qos: .userInitiated, attributes: .concurrent)

    /// Renders `fileURL` into `format` (a `dot -T` format such as "pdf", "svg", "png").
    /// Completion is called on the main queue unless the job was cancelled.
    @discardableResult
    static func render(
        fileURL: URL,
        format: String,
        engine: LayoutEngine,
        completion: @escaping (Result<RenderResult, Error>) -> Void
    ) -> RenderJob {
        let job = RenderJob()
        renderQueue.async {
            let result: Result<RenderResult, Error>
            if let dot = dotExecutable() {
                var arguments = ["-T\(format)"]
                if engine != .automatic {
                    arguments.append("-K\(engine.rawValue)")
                }
                arguments.append(fileURL.path)
                result = Result {
                    try job.run(
                        executable: dot,
                        arguments: arguments,
                        workingDirectory: fileURL.deletingLastPathComponent()
                    )
                }
            } else {
                result = .failure(GraphvizError.notInstalled)
            }
            DispatchQueue.main.async {
                if !job.isCancelled {
                    completion(result)
                }
            }
        }
        return job
    }

    private static let lock = NSLock()
    private static var cachedExecutable: URL?

    /// Locates the `dot` executable. GUI apps do not inherit the shell's PATH, so look in
    /// the usual install locations and fall back to asking a login shell.
    static func dotExecutable() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedExecutable, FileManager.default.isExecutableFile(atPath: cached.path) {
            return cached
        }

        var candidates: [String] = []
        if let configured = UserDefaults.standard.string(forKey: "DotPath"), !configured.isEmpty {
            candidates.append((configured as NSString).expandingTildeInPath)
        }
        candidates += [
            "/opt/homebrew/bin/dot",
            "/usr/local/bin/dot",
            "/opt/local/bin/dot",
            "/usr/bin/dot",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            cachedExecutable = URL(fileURLWithPath: found)
        } else if let found = lookupWithLoginShell() {
            cachedExecutable = URL(fileURLWithPath: found)
        }
        return cachedExecutable
    }

    private static func lookupWithLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v dot"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
