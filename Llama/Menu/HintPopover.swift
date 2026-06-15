import AppKit

/// A small speech-bubble-style popover anchored to the status bar icon.
///
/// Used for lightweight, dismissible feedback -- e.g. the first-launch
/// "Hello, I'm Llama" greeting, and deeplink install acknowledgements
/// like "Downloading <model>…". The popover auto-dismisses when the menu
/// opens (user clicked the icon) or when the user clicks outside it.
final class HintPopover: NSViewController, NSPopoverDelegate {
  private let message: String
  private let popover = NSPopover()
  private var observer: NSObjectProtocol?
  private var clickMonitor: Any?

  init(message: String) {
    self.message = message
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) not supported")
  }

  override func loadView() {
    let label = NSTextField(labelWithString: message)
    label.font = .systemFont(ofSize: 13)
    label.textColor = .controlTextColor
    label.isBezeled = false
    label.drawsBackground = false
    label.isEditable = false
    label.isSelectable = false
    label.sizeToFit()

    let contentView = NSView(
      frame: NSRect(
        x: 0,
        y: 0,
        width: label.frame.width + 32,
        height: label.frame.height + 24
      ))

    label.frame.origin = NSPoint(x: 16, y: 12)
    contentView.addSubview(label)

    view = contentView
  }

  /// Shows the popover pointing to the status bar button.
  /// Dismisses when the user clicks the menu bar icon or clicks outside.
  func show(from statusItem: NSStatusItem) {
    guard let button = statusItem.button else { return }

    popover.contentViewController = self
    popover.delegate = self
    popover.behavior = .semitransient
    popover.animates = true

    popover.show(
      relativeTo: button.bounds,
      of: button,
      preferredEdge: .minY
    )

    // Dismiss as soon as the user opens the menu -- the menu itself is the
    // place where install progress is surfaced, so the bubble has done its job.
    observer = NotificationCenter.default.addObserver(
      forName: NSMenu.didBeginTrackingNotification,
      object: statusItem.menu,
      queue: .main
    ) { [weak self] _ in
      self?.popover.close()
    }

    // Also dismiss on any click outside the bubble itself.
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      guard let self else { return }

      DispatchQueue.main.async {
        guard let window = self.popover.contentViewController?.view.window else { return }

        let screenPoint: NSPoint
        if let eventWindow = event.window {
          let rect = NSRect(origin: event.locationInWindow, size: .zero)
          screenPoint = eventWindow.convertToScreen(rect).origin
        } else {
          screenPoint = event.locationInWindow
        }

        if !window.frame.contains(screenPoint) {
          self.popover.close()
        }
      }
    }
  }

  func popoverDidClose(_ notification: Notification) {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
    if let clickMonitor {
      NSEvent.removeMonitor(clickMonitor)
      self.clickMonitor = nil
    }
  }
}
