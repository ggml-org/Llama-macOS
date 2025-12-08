import AppKit

final class FooterView: NSView {
  private let onCheckForUpdates: () -> Void
  private let onOpenSettings: () -> Void
  private let onQuit: () -> Void

  init(
    onCheckForUpdates: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void,
    onQuit: @escaping () -> Void
  ) {
    self.onCheckForUpdates = onCheckForUpdates
    self.onOpenSettings = onOpenSettings
    self.onQuit = onQuit
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize {
    NSSize(width: Layout.menuWidth, height: 28)
  }

  private func setup() {
    // Version Button
    let versionButton = NSButton(
      title: "", target: self, action: #selector(checkForUpdatesClicked))
    versionButton.attributedTitle = NSAttributedString(
      string: appVersionText,
      attributes: Theme.secondaryAttributes(color: Theme.Colors.textPrimary)
    )
    versionButton.isBordered = false
    versionButton.translatesAutoresizingMaskIntoConstraints = false

    // Llama Version Label
    let llamaLabel = Theme.tertiaryLabel(" · llama.cpp \(AppInfo.llamaCppVersion)")
    llamaLabel.translatesAutoresizingMaskIntoConstraints = false

    // Settings Button
    let settingsButton = FooterButton(
      title: "Settings", target: self, action: #selector(openSettingsClicked))
    settingsButton.translatesAutoresizingMaskIntoConstraints = false

    // Quit Button
    let quitButton = FooterButton(title: "Quit", target: self, action: #selector(quitClicked))
    quitButton.translatesAutoresizingMaskIntoConstraints = false

    addSubview(versionButton)
    addSubview(llamaLabel)
    addSubview(settingsButton)
    addSubview(quitButton)

    NSLayoutConstraint.activate([
      // Left side
      versionButton.leadingAnchor.constraint(
        equalTo: leadingAnchor,
        constant: Layout.outerHorizontalPadding + Layout.innerHorizontalPadding),
      versionButton.centerYAnchor.constraint(equalTo: centerYAnchor),

      llamaLabel.leadingAnchor.constraint(equalTo: versionButton.trailingAnchor),
      llamaLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

      // Right side
      quitButton.trailingAnchor.constraint(
        equalTo: trailingAnchor,
        constant: -(Layout.outerHorizontalPadding + Layout.innerHorizontalPadding)),
      quitButton.centerYAnchor.constraint(equalTo: centerYAnchor),

      settingsButton.trailingAnchor.constraint(equalTo: quitButton.leadingAnchor, constant: -5),
      settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @objc private func checkForUpdatesClicked() { onCheckForUpdates() }
  @objc private func openSettingsClicked() { onOpenSettings() }
  @objc private func quitClicked() { onQuit() }

  private var appVersionText: String {
    #if DEBUG
      return "dev"
    #else
      return AppInfo.shortVersion == "0.0.0"
        ? "build \(AppInfo.buildNumber)"
        : AppInfo.shortVersion
    #endif
  }
}

/// A simple bordered button matching the footer style
private class FooterButton: NSButton {
  init(title: String, target: AnyObject?, action: Selector) {
    super.init(frame: .zero)
    self.attributedTitle = NSAttributedString(
      string: title,
      attributes: Theme.secondaryAttributes(color: Theme.Colors.textSecondary)
    )
    self.target = target
    self.action = action
    self.bezelStyle = .inline
    self.isBordered = false  // We draw our own border
    self.wantsLayer = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var wantsUpdateLayer: Bool { true }

  override var intrinsicContentSize: NSSize {
    let size = super.intrinsicContentSize
    return NSSize(width: size.width + 8, height: size.height + 4)
  }

  override func updateLayer() {
    layer?.cornerRadius = 5
    layer?.borderWidth = 1
    // Use Theme.Colors.border instead of .separatorColor because CALayers don't support vibrancy.
    // See Theme.swift for details.
    layer?.setBorderColor(Theme.Colors.border, in: self)

    let bgColor: NSColor = isHighlighted ? Theme.Colors.subtleBackground : .clear
    layer?.setBackgroundColor(bgColor, in: self)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override var isHighlighted: Bool {
    didSet { needsDisplay = true }
  }
}
