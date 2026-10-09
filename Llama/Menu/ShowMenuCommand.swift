import Cocoa

/// AppleScript command handler for "show menu"
/// Usage: tell application "Llama" to show menu
///
/// Opens the menu bar menu. Exists so scripts (UI screenshots in development,
/// mostly) can open it deterministically: clicking the status item through
/// System Events toggles the menu, so a script can't tell whether it opened or
/// closed it.
///
/// There's no "hide menu" counterpart because it couldn't work: an open menu
/// runs its own event loop, which doesn't service Apple events, so any command
/// sent to the app -- this one included -- waits until the menu closes (or
/// the sender times out). Closing it is an Escape key press.
class ShowMenuCommand: NSScriptCommand {
  override func performDefaultImplementation() -> Any? {
    // Goes through the same notification the global-input panel uses, which
    // lands in `MenuController.openMenu()` -- the one safe way to open the menu
    // from code (see there for why).
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .LBOpenMenu, object: nil)
    }
    return nil
  }
}
