import AppKit
import Sentry

/// Presents app-modal panels with Sentry's app-hang reporting suspended for the
/// duration, so an intentional block doesn't get reported as a freeze.
///
/// `runModal()` spins a nested run loop that blocks the main thread for as long
/// as the user reads the dialog. Sentry's V1 hang tracker -- the only one
/// available on macOS (V2, which classifies these correctly, is iOS/tvOS only)
/// -- can't distinguish that from a hang, so it reports "App hanging for at
/// least 2000 ms" every time a user lingers on an alert. That's pure noise, and
/// historically our single largest source of app-hang events. Sentry considers
/// the root cause unfixable on macOS and points at `pauseAppHangTracking()` as
/// the supported mitigation, which is what we do here.
///
/// The tracker samples the main thread's stack at the moment it declares a hang,
/// which can land anywhere in the presentation -- including while the panel is
/// still being built, since that loads a nib and creates a window. So the
/// suppression has to span the *whole* thing, construction included. An earlier
/// version wrapped only `runModal()` and kept reporting hangs against
/// `NSAlert.init`; `showAlert` exists so that mistake isn't expressible.
enum ModalPresentation {
    // Modals can nest (an alert raised from an open panel), but the SDK's
    // pause/resume is a plain on/off switch -- so we count depth and let only
    // the outermost presentation toggle it. Without the count, an inner modal
    // finishing would resume tracking while the outer one is still on screen.
    // Only ever touched from the main actor, via `run(_:)`.
    private static var depth = 0

    /// Shows a single-button ("OK") alert with hang reporting suspended.
    ///
    /// Prefer this over building an `NSAlert` by hand -- it's what keeps the
    /// suppression around the entire presentation. An alert needing more than an
    /// OK button can use `run(_:)`, but has to build the alert inside it.
    ///
    /// Activation is left to the caller: an accessory (menu-bar) app has to
    /// `NSApp.activate` to foreground the alert, but not every caller wants to
    /// pull the app forward.
    @MainActor
    static func showAlert(style: NSAlert.Style, title: String, body: String? = nil) {
        run {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = title
            if let body { alert.informativeText = body }
            alert.addButton(withTitle: "OK")
            return alert.runModal()
        }
    }

    /// Presents a modal with app-hang reporting suspended for its duration.
    ///
    /// `body` must both build and run the panel -- see the note above on why
    /// construction has to be inside the wrapper.
    @MainActor
    @discardableResult
    static func run<T>(_ body: () -> T) -> T {
        depth += 1
        if depth == 1 {
            SentrySDK.pauseAppHangTracking()
        }
        defer {
            depth -= 1
            if depth == 0 {
                SentrySDK.resumeAppHangTracking()
            }
        }
        return body()
    }
}
