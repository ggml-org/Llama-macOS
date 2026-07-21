import AppKit
import OSLog

/// Tracks whether an app-modal panel (`runModal()`) is currently on screen, so
/// Sentry's app-hang detector can tell an intentional modal apart from a real
/// freeze.
///
/// `runModal()` spins a nested run loop that blocks the main thread for as long
/// as the user reads the dialog. Sentry's V1 hang tracker -- the only one
/// available on macOS (V2, which classifies these correctly, is iOS/tvOS only)
/// -- can't distinguish that from a hang, so it reports "App hanging for at
/// least 2000 ms" every time a user lingers on an alert. That's pure noise, and
/// historically our single largest source of app-hang events.
///
/// We can't reliably filter these in `beforeSend` by matching a `runModal`
/// stack frame: `beforeSend` runs off the main thread before server-side
/// symbolication, so frame function names aren't dependable there. Instead we
/// track modal presentation explicitly with this flag and drop app hangs while
/// it's set (see `beforeSend` in `LlamaApp`).
enum ModalPresentation {
    private static let log = Logger(subsystem: Logging.subsystem, category: "ModalPresentation")

    // Guards `depth`. `isActive` is read from Sentry's `beforeSend` thread while
    // `run(_:)` mutates it on the main thread, so access needs a lock.
    private static let lock = NSLock()
    private static var depth = 0

    /// Whether a modal is currently being presented. Safe to read from any
    /// thread -- Sentry calls `beforeSend` off the main thread.
    static var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return depth > 0
    }

    /// Runs `body` (a `runModal()` call) with the modal flag set for its
    /// duration, so an app hang reported while the modal is up can be dropped.
    @MainActor
    @discardableResult
    static func run<T>(_ body: () -> T) -> T {
        lock.lock()
        depth += 1
        let entered = depth
        lock.unlock()
        log.debug("Modal presentation begin (depth now \(entered, privacy: .public))")
        defer {
            lock.lock()
            depth -= 1
            let remaining = depth
            lock.unlock()
            log.debug("Modal presentation end (depth now \(remaining, privacy: .public))")
        }
        return body()
    }
}
