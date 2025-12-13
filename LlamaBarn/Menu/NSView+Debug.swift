import AppKit
import ObjectiveC

extension NSView {
  /// Swizzles `viewDidMoveToWindow` to automatically apply debug outlines to all views
  /// when the `LB_DEBUG_UI` environment variable is set.
  static func swizzleDebugBehavior() {
    guard AppInfo.isUIDebugEnabled else { return }

    let originalSelector = #selector(viewDidMoveToWindow)
    let swizzledSelector = #selector(debug_viewDidMoveToWindow)

    guard let originalMethod = class_getInstanceMethod(NSView.self, originalSelector),
      let swizzledMethod = class_getInstanceMethod(NSView.self, swizzledSelector)
    else {
      return
    }

    method_exchangeImplementations(originalMethod, swizzledMethod)
  }

  @objc func debug_viewDidMoveToWindow() {
    // Call the original implementation (which is now swizzled to this method name)
    self.debug_viewDidMoveToWindow()
    self.applyDebugOutline()
  }

  /// Applies a colored border to the view based on its type.
  /// Used for visual debugging of the view hierarchy.
  func applyDebugOutline() {
    guard AppInfo.isUIDebugEnabled else { return }

    // Only outline views that are explicitly interesting:
    // 1. Key AppKit components (Stacks, Controls, Text, Images)
    // 2. Custom views defined in the main bundle (e.g. ItemView, HeaderView)
    // 3. Direct subviews of custom views (captures structural containers like backgroundView)
    let isInterestingSystemView =
      self is NSStackView || self is NSTextField || self is NSImageView || self is NSControl
    let isCustomView = Bundle(for: type(of: self)) == Bundle.main
    let isDirectChildOfCustomView =
      self.superview.map { Bundle(for: type(of: $0)) == Bundle.main } ?? false

    guard isInterestingSystemView || isCustomView || isDirectChildOfCustomView else { return }

    wantsLayer = true
    layer?.borderWidth = 1

    let color: NSColor
    switch self {
    case is NSStackView:
      color = .systemGreen  // Layout containers
    case is NSTextField:
      color = .systemBlue  // Text labels and inputs
    case is NSImageView:
      color = .systemOrange  // Icons and images
    case is NSControl:
      color = .systemPurple  // Interactive controls
    default:
      color = .systemRed  // Custom views
    }

    // Use translucent colors to handle overlapping views
    layer?.borderColor = color.withAlphaComponent(0.5).cgColor
  }
}
