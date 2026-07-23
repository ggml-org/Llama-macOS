import AppKit

/// Shared UI layout constants and helpers for NSMenu custom rows.
enum Layout {
  /// Standard menu width for all items. Normally `baseMenuWidth`; widened (up to
  /// `maxMenuWidth`) by `fitMenuWidth` when an installed model's title wouldn't
  /// fit otherwise. Row views capture this at init, so it must be set before a
  /// menu build creates any views (see `MenuController.rebuildMenu`).
  static private(set) var menuWidth: CGFloat = baseMenuWidth
  /// Default menu width — enough for every catalog model (no org prefix).
  private static let baseMenuWidth: CGFloat = 300
  /// Hard cap on widening: long org-prefixed ids truncate past this rather than
  /// stretch the menu indefinitely.
  private static let maxMenuWidth: CGFloat = 400

  /// Sets `menuWidth` so the widest given row title fits, clamped to
  /// [`baseMenuWidth`, `maxMenuWidth`]. Called with the installed models'
  /// rendered titles on every menu rebuild; with none installed (or all short)
  /// it resets to the base width.
  static func fitMenuWidth(toTitles titles: [NSAttributedString]) {
    // Measure through an actual label rather than NSAttributedString.size():
    // the string measure under-reports what NSTextField needs (cell padding,
    // attachment layout), so rows sized by it still truncate.
    let label = Theme.primaryLabel()
    let maxTitleWidth =
      titles.map { title -> CGFloat in
        label.attributedStringValue = title
        return ceil(label.intrinsicContentSize.width)
      }.max() ?? 0
    // Chrome around the title in a model row: outer + inner padding on both
    // sides, the leading icon and its 6pt spacing to the text, plus the root
    // stack's two 6pt gaps around the flexible spacer (present even when the
    // trailing accessories are hidden) — see ModelItemView.setupLayout.
    let rowChrome =
      (outerHorizontalPadding + innerHorizontalPadding) * 2 + iconViewSize + 6 + 12
    menuWidth = min(max(maxTitleWidth + rowChrome, baseMenuWidth), maxMenuWidth)
  }
  /// Distance from menu edge to background view (used in all menu items).
  static let outerHorizontalPadding: CGFloat = 5
  /// Distance from background edge to content (used in all menu items).
  static let innerHorizontalPadding: CGFloat = 8
  /// Vertical spacing between content and background edge (used in ItemView).
  static let verticalPadding: CGFloat = 4
  /// Rounded corner radius for highlights.
  static let cornerRadius: CGFloat = 6
  /// Size for UI icons (model icons, chevrons, cancel buttons).
  static let uiIconSize: CGFloat = 16
  /// Size for IconView containers (circular backgrounds for installed model icons).
  static let iconViewSize: CGFloat = 28
  /// Vertical spacing between text lines in stacked labels (e.g., model name and metadata).
  static let textLineSpacing: CGFloat = 2
  /// Available width for content inside menu items (menu width minus outer and inner padding).
  static var contentWidth: CGFloat {
    menuWidth - (outerHorizontalPadding * 2) - (innerHorizontalPadding * 2)
  }

  /// Constrains a view to the standard UI icon size (width and height).
  /// Uses `equalToConstant` so icons never shrink when other row content
  /// (long titles, hover buttons appearing) competes for width — without this,
  /// autolayout silently squeezes icons instead of truncating the subtitle.
  static func constrainToIconSize(_ view: NSView) {
    view.widthAnchor.constraint(equalToConstant: uiIconSize).isActive = true
    view.heightAnchor.constraint(equalToConstant: uiIconSize).isActive = true
  }
}

extension NSView {
  /// Creates a fixed-width spacer view for use in stack views.
  static func spacer(width: CGFloat) -> NSView {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.widthAnchor.constraint(equalToConstant: width).isActive = true
    return view
  }

  /// Creates a flexible spacer that expands to fill available space.
  static func flexibleSpacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.init(1), for: .horizontal)
    return view
  }

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
