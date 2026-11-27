import AppKit

/// Shared helper for presenting simple app-modal alerts.
enum ModalPresentation {
    /// Shows a single-button ("OK") alert.
    ///
    /// Activation is left to the caller: an accessory (menu-bar) app has to
    /// `NSApp.activate` to foreground the alert, but not every caller wants to
    /// pull the app forward.
    @MainActor
    static func showAlert(style: NSAlert.Style, title: String, body: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        if let body { alert.informativeText = body }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
