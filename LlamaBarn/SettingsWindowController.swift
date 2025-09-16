import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
  static let shared = SettingsWindowController()

  private init() {
    let controller = NSHostingController(rootView: SettingsView())
    let window = NSWindow(contentViewController: controller)
    window.title = "Settings"
    window.setContentSize(NSSize(width: 420, height: 280))
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show() {
    guard let window else { return }
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
