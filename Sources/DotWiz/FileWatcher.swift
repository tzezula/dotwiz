import Foundation

/// Watches a single file path and invokes `onChange` (on the main queue) whenever the
/// file's contents change.
///
/// Many editors save atomically (write a temp file, then rename it over the original) or
/// rename the original to a backup before writing a new file. Both break a watch bound to
/// the original inode, so on delete/rename the watcher re-attaches to whatever file
/// appears at the same path.
final class FileWatcher {
    private let path: String
    private let onChange: () -> Void
    private let debounceInterval: TimeInterval
    private var source: DispatchSourceFileSystemObject?
    private var pendingNotification: DispatchWorkItem?
    private var reattachTimer: Timer?

    init(url: URL, debounceInterval: TimeInterval = 0.15, onChange: @escaping () -> Void) {
        self.path = url.path
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        if !attach() {
            scheduleReattach()
        }
    }

    func stop() {
        reattachTimer?.invalidate()
        reattachTimer = nil
        pendingNotification?.cancel()
        pendingNotification = nil
        source?.cancel()
        source = nil
    }

    /// Opens the file and installs a dispatch source on it. Returns false if the file
    /// does not currently exist.
    private func attach() -> Bool {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let events = source.data
            if !events.intersection([.delete, .rename, .revoke]).isEmpty {
                // The inode we watch is gone from this path; follow the path instead.
                source.cancel()
                self.source = nil
                self.scheduleReattach()
            }
            self.notifyDebounced()
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
        return true
    }

    private func scheduleReattach() {
        reattachTimer?.invalidate()
        // Retry quickly at first (atomic saves recreate the file within milliseconds),
        // then keep polling in case the file is restored later.
        var attempts = 0
        reattachTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            attempts += 1
            if self.attach() {
                timer.invalidate()
                self.reattachTimer = nil
                self.notifyDebounced()
            } else if attempts == 20 {
                timer.invalidate()
                self.reattachTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                    guard let self else {
                        timer.invalidate()
                        return
                    }
                    if self.attach() {
                        timer.invalidate()
                        self.reattachTimer = nil
                        self.notifyDebounced()
                    }
                }
            }
        }
    }

    /// Coalesces bursts of events (editors often emit several per save) into one callback.
    private func notifyDebounced() {
        pendingNotification?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pendingNotification = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}
