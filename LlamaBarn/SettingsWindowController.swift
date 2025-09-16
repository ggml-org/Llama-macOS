import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  static let shared = SettingsWindowController()

  private var shouldRestoreAccessoryOnClose = false

  private init() {
    let controller = NSHostingController(rootView: SettingsView())
    let window = NSWindow(contentViewController: controller)
    window.title = "Settings"
    window.setContentSize(NSSize(width: 420, height: 280))
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func show() {
    guard let window else { return }
    if NSApp.activationPolicy() != .regular {
      shouldRestoreAccessoryOnClose = true
      NSApp.setActivationPolicy(.regular)
    }
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  var isVisible: Bool {
    window?.isVisible == true
  }

  func windowWillClose(_ notification: Notification) {
    if shouldRestoreAccessoryOnClose {
      shouldRestoreAccessoryOnClose = false
      NSApp.setActivationPolicy(.accessory)
    }
  }
}
