import AppKit

/// A standard menu item view with an icon, two lines of text, and an accessory area.
/// Reduces boilerplate for CatalogModelItemView and InstalledModelItemView.
class StandardItemView: TitledItemView {
  let iconView = IconView()
  let accessoryStack = NSStackView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setupStandardLayout()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setupStandardLayout() {
    // Text column
    let textColumn = makeTextStack()

    // Leading: Icon + Text
    let leading = NSStackView(views: [iconView, textColumn])
    leading.orientation = .horizontal
    leading.alignment = .centerY
    leading.spacing = 6

    // Spacer to push accessory stack to the right
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Accessory Stack (initially empty)
    accessoryStack.orientation = .horizontal
    accessoryStack.alignment = .centerY
    accessoryStack.spacing = 6

    // Root Stack
    let rootStack = NSStackView(views: [leading, spacer, accessoryStack])
    rootStack.orientation = .horizontal
    rootStack.alignment = .centerY  // Align everything to center vertically
    rootStack.spacing = 6

    contentView.addSubview(rootStack)
    rootStack.pinToSuperview()
  }
}
