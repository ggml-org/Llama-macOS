import Cocoa

/// AppleScript command handler for "show global input"
/// Usage: tell application "Llama" to show global input
///
/// Opens the global-input capture panel on demand -- creating the controller if
/// the experiment flag left it dormant -- so we can bring the panel up while
/// iterating on it without enabling globalInputEnabled.
/// DEBUG-only: a no-op in release builds so the dormant experiment can't be
/// summoned in production.
class ShowGlobalInputCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    #if DEBUG
      NotificationCenter.default.post(name: .LBShowGlobalInput, object: nil)
    #endif
    return nil
  }
}
