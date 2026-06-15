import AppKit

/// Utility for clipboard operations.
/// Centralizes pasteboard access so callers don't repeat the clear-and-set pattern.
enum Clipboard {
  /// Copies the given text to the system clipboard, replacing any previous content.
  static func copy(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }
}
