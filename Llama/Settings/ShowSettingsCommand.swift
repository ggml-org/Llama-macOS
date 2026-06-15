import Cocoa

/// AppleScript command handler for "show settings"
/// Usage: tell application "Llama" to show settings
class ShowSettingsCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    DispatchQueue.main.async {
      SettingsWindowController.shared.showSettings()
    }
    return nil
  }
}
