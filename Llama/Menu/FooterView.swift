import AppKit

final class FooterView: ItemView {
  private let onCheckForUpdates: () -> Void
  private let onOpenSettings: () -> Void
  private let onQuit: () -> Void
  /// Build of the `llama` binary actually in use, or nil if not yet known.
  private let llamaVersion: String?
  /// Where that binary comes from -- unmanaged installs get a marker ("· brew"
  /// or "· ext") so a stale version isn't mistaken for a bug.
  private let llamaOrigin: LlamaBinaries.Origin

  init(
    llamaVersion: String?,
    llamaOrigin: LlamaBinaries.Origin,
    onCheckForUpdates: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void,
    onQuit: @escaping () -> Void
  ) {
    self.llamaVersion = llamaVersion
    self.llamaOrigin = llamaOrigin
    self.onCheckForUpdates = onCheckForUpdates
    self.onOpenSettings = onOpenSettings
    self.onQuit = onQuit
    super.init(frame: .zero)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { false }

  override var intrinsicContentSize: NSSize {
    NSSize(width: Layout.menuWidth, height: 28)
  }

  private func setup() {
    // Version label -- a plain label (not an NSButton) so its text starts at the
    // exact content edge; a borderless button's cell adds a ~2px inset that left
    // it looking misaligned against the header and model rows. Clickable via a
    // gesture, matching the menu's other inline links (WebUI, "models").
    let versionLabel = Theme.secondaryLabel()
    versionLabel.attributedStringValue = NSAttributedString(
      string: appVersionText,
      attributes: Theme.secondaryAttributes(color: Theme.Colors.textPrimary)
    )
    versionLabel.isSelectable = false
    versionLabel.translatesAutoresizingMaskIntoConstraints = false
    let versionClick = NSClickGestureRecognizer(
      target: self, action: #selector(checkForUpdatesClicked))
    versionLabel.addGestureRecognizer(versionClick)

    // Llama Version Label -- the build of the binary actually being driven.
    // Unmanaged installs get a marker ("· brew" for Homebrew, "· ext" for
    // anything else), since the app won't update them and their version can
    // legitimately trail the pin.
    let marker: String
    switch llamaOrigin {
    case .managed: marker = ""
    case .brew: marker = " · brew"
    case .external: marker = " · ext"
    }
    let llamaText = llamaVersion.map { " · llama.cpp \($0)\(marker)" } ?? " · llama.cpp"
    let llamaLabel = Theme.tertiaryLabel(llamaText)
    llamaLabel.translatesAutoresizingMaskIntoConstraints = false

    // Settings Button
    let settingsButton = FooterButton(
      title: "Settings", target: self, action: #selector(openSettingsClicked))
    settingsButton.translatesAutoresizingMaskIntoConstraints = false

    // Quit Button
    let quitButton = FooterButton(title: "Quit", target: self, action: #selector(quitClicked))
    quitButton.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(versionLabel)
    contentView.addSubview(llamaLabel)
    contentView.addSubview(settingsButton)
    contentView.addSubview(quitButton)

    NSLayoutConstraint.activate([
      // Left side
      versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      versionLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

      llamaLabel.leadingAnchor.constraint(equalTo: versionLabel.trailingAnchor),
      llamaLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

      // Right side
      quitButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      quitButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

      settingsButton.trailingAnchor.constraint(equalTo: quitButton.leadingAnchor, constant: -5),
      settingsButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  @objc private func checkForUpdatesClicked() { onCheckForUpdates() }
  @objc private func openSettingsClicked() { onOpenSettings() }
  @objc private func quitClicked() { onQuit() }

  private var appVersionText: String {
    #if DEBUG
      return "dev"
    #else
      let version = AppInfo.shortVersion
      if version == "0.0.0" { return AppInfo.buildNumber }
      return version
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
