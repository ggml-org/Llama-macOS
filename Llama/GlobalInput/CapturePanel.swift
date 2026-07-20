import AppKit

/// A borderless, floating panel that hosts the capture field -- the Spotlight /
/// Raycast pattern.
///
/// Key traits (all required to feel like Spotlight):
/// - `.nonactivatingPanel`: takes key focus for text input without fully
///   activating Llama, so dismissing returns the user to whatever app they were
///   in with its state intact.
/// - `.floating` level + `canJoinAllSpaces`: appears above other apps and on
///   whichever Space is active, including full-screen.
/// - Resigns key / Esc dismiss it, matching the launcher convention.
final class CapturePanel: NSPanel {
  /// Called when the panel loses key status (click-away) so the controller can
  /// treat it as a cancel.
  var onResignKey: (() -> Void)?

  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect,
      // `.nonactivatingPanel` is what keeps the owning app from activating.
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    isFloatingPanel = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

    // Chromeless, rounded, translucent -- the launcher look.
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    titlebarAppearsTransparent = true
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
  }

  // Borderless windows return false by default; we need key to accept typing.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  // Esc -> dismiss, matching Spotlight/Raycast.
  override func cancelOperation(_ sender: Any?) {
    onResignKey?()
  }

  // Click-away (focus lost) dismisses too.
  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }
}
