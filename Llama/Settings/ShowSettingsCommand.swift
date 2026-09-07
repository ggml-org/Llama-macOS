import Cocoa

/// AppleScript command handler for "show settings"
/// Usage: tell application "Llama" to show settings
///        tell application "Llama" to show settings tab "Network"
///
/// The optional tab names a section by the same string the sidebar shows, so
/// the command can open straight to a pane instead of always landing on
/// General and leaving the caller to click.
class ShowSettingsCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    // Read before the hop to the main queue: the command's arguments belong to
    // the event being handled, not to whenever the block happens to run.
    let name = evaluatedArguments?["tab"] as? String
    let tab = name.flatMap(SettingsTab.init(sidebarName:))

    // An unrecognised name is the caller's mistake, and silently opening on
    // some other pane would look like the command worked. Fail the event so
    // the mistake surfaces where it was made.
    if let name, tab == nil {
      scriptErrorNumber = errAEEventFailed
      scriptErrorString = "No settings tab named \"\(name)\"."
      return nil
    }

    DispatchQueue.main.async {
      SettingsWindowController.shared.showSettings(tab: tab)
    }
    return nil
  }
}
