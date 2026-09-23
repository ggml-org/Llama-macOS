import Cocoa

/// AppleScript command handler for "show global input"
/// Usage: tell application "Llama" to show global input
///
/// Opens the global-input capture panel on demand. Lets people trigger the panel
/// from their own launcher (Raycast, Keyboard Maestro, Shortcuts, ...) instead of
/// taking over the ⌥Space hotkey.
///
/// Takes no arguments and returns nothing: showing the panel is all it can do.
class ShowGlobalInputCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    DispatchQueue.main.async {
      GlobalInputController.shared.show()
    }
    return nil
  }
}
