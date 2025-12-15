import AppKit

/// Shared UI layout constants and helpers for NSMenu custom rows.
enum Layout {
  /// Standard menu width for all items.
  static let menuWidth: CGFloat = 300
  /// Distance from menu edge to background view (used in all menu items and headers).
  static let outerHorizontalPadding: CGFloat = 5
  /// Distance from background edge to content (used in all menu items and headers).
  static let innerHorizontalPadding: CGFloat = 8
  /// Vertical spacing between content and background edge (used in ItemView).
  static let verticalPadding: CGFloat = 4
  /// Rounded corner radius for highlights.
  static let cornerRadius: CGFloat = 6
  /// Size for UI icons (model icons, chevrons, cancel buttons).
  static let uiIconSize: CGFloat = 16
  /// Size for IconView containers (circular backgrounds for installed model icons).
  static let iconViewSize: CGFloat = 28
  /// Maximum width for download progress labels.
  static let progressWidth: CGFloat = 48
  /// Vertical spacing between text lines in stacked labels (e.g., model name and metadata).
  static let textLineSpacing: CGFloat = 1
}

extension NSView {
  /// Applies or clears the standard selection highlight background on a container view.
  /// Uses dynamic colors resolved for the view's effective appearance and sets a rounded corner.
  func setHighlight(_ highlighted: Bool, cornerRadius: CGFloat = Layout.cornerRadius) {
    wantsLayer = true
    let color: NSColor = highlighted ? Theme.Colors.subtleBackground : .clear
    layer?.setBackgroundColor(color, in: self)
    layer?.cornerRadius = cornerRadius
  }

  /// Pins this view to all edges of its superview with optional padding.
  /// Sets translatesAutoresizingMaskIntoConstraints to false automatically.
  func pinToSuperview(
    top: CGFloat = 0,
    leading: CGFloat = 0,
    trailing: CGFloat = 0,
    bottom: CGFloat = 0
  ) {
    // Fail gracefully if no superview exists (shouldn't happen in normal usage)
    guard let superview = superview else { return }
    // Required to use Auto Layout constraints; must be set before activating constraints
    translatesAutoresizingMaskIntoConstraints = false
    // Batch activate all constraints together for better performance than activating individually
    NSLayoutConstraint.activate([
      // Leading/trailing are localization-aware (adapt for RTL languages)
      leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: leading),
      // Negative constant for trailing because padding is measured from the edge inward
      trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -trailing),
      // Top constraint with positive padding moving down
      topAnchor.constraint(equalTo: superview.topAnchor, constant: top),
      // Negative constant for bottom because padding is measured from the edge inward
      bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -bottom),
    ])
  }
}

extension NSMenuItem {
  /// Creates a disabled NSMenuItem backed by a custom view and optional minimum height.
  static func viewItem(with view: NSView, minHeight: CGFloat? = nil) -> NSMenuItem {
    let item = NSMenuItem()
    item.isEnabled = false
    item.view = view
    if let minHeight {
      view.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
    }
    return item
  }
}
