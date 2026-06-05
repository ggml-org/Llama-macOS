import AppKit

/// Surfaces the app-owned CLI install in the menu: a "setting up…" banner while
/// installing, or an error with a retry link if it failed. Shown only when the
/// install manager is mid-install or has failed; a ready binary shows nothing.
final class CLISetupView: ItemView {
  override var highlightEnabled: Bool { false }

  private let state: LlamaInstallManager.State

  init(state: LlamaInstallManager.State) {
    self.state = state
    super.init(frame: .zero)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setup() {
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true

    let views: [NSView]
    switch state {
    case .installing:
      let title = Theme.primaryLabel("Setting up llama…")
      let description = wrappingLabel(
        "Downloading the engine. This only happens once.")
      views = [title, description]

    case .failed(let message):
      let title = Theme.primaryLabel("Couldn’t set up llama")
      let description = wrappingLabel(message)
      views = [title, description, actionLink("→ Retry")]

    case .externalTooOld(let version):
      let title = Theme.primaryLabel("Update llama.cpp")
      let description = wrappingLabel(
        "Your llama.cpp (\(version.tag)) is older than the recommended "
          + "\(LlamaBinaries.minVersion.tag). Update it with “brew upgrade llama.cpp”.")
      views = [title, description, actionLink("→ Re-check")]

    case .idle:
      // Not rendered when idle; guard anyway so the view is never blank-but-present.
      views = []
    }

    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = Layout.textLineSpacing
    if views.count >= 2 { stack.setCustomSpacing(8, after: views[1]) }

    contentView.addSubview(stack)
    stack.pinToSuperview()
  }

  /// A tappable link row (e.g. "→ Retry") that re-runs the CLI readiness check.
  private func actionLink(_ title: String) -> NSTextField {
    let link = Theme.secondaryLabel()
    link.attributedStringValue = NSAttributedString(
      string: title,
      attributes: [.foregroundColor: NSColor.linkColor, .font: Theme.Fonts.secondary])
    link.isSelectable = false
    addGesture(to: link, action: #selector(recheck))
    return link
  }

  private func wrappingLabel(_ text: String) -> NSTextField {
    let label = Theme.tertiaryLabel(text)
    label.cell?.wraps = true
    label.cell?.isScrollable = false
    label.usesSingleLineMode = false
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.preferredMaxLayoutWidth = Layout.contentWidth
    return label
  }

  @objc private func recheck() {
    NotificationCenter.default.post(name: .LBRecheckCLI, object: nil)
  }
}
