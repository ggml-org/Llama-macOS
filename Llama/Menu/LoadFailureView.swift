import AppKit

/// Shown on a model page when the model's last load attempt failed, so a Load
/// (or a chat request) that went nowhere is explained instead of leaving the
/// page looking idle.
///
/// The server only reports *that* the load failed (`failed` in `/models`), not
/// why. The cause worth naming is an engine too old for the model -- a newer
/// catalog model on an older Homebrew `llama` fails with "unknown model
/// architecture" -- and that's the one case the user can fix. So when the
/// engine is unmanaged and older than the build the app ships, the note blames
/// it (hedged with "may": an old engine can also fail for other reasons) and
/// says how to update. The app-managed engine is kept at the pinned build, so
/// there's no such advice to give there and the note stays generic.
final class LoadFailureView: ItemView {
  override var highlightEnabled: Bool { false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setup()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setup() {
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true

    let title = Theme.primaryLabel("Couldn’t load this model")
    let description = wrappingLabel(Self.explanation())

    // Same title + wrapped description pairing as the engine setup banner
    // (`CLISetupView`), the menu's other "something needs your attention" note.
    let stack = NSStackView(views: [title, description])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = Layout.textLineSpacing

    contentView.addSubview(stack)
    stack.pinToSuperview()
  }

  /// The likely cause and what to do about it, from the engine in use.
  private static func explanation() -> String {
    let install = LlamaInstallManager.shared
    guard install.currentOrigin != .managed,
      let version = install.currentVersion,
      version < LlamaBinaries.targetVersion
    else {
      return "llama.cpp exited while loading it."
    }
    // Homebrew has one known update command; anything else is updated however
    // it was installed, which the app can't tell. Either way the running
    // server keeps the old binary until Llama restarts.
    let howTo =
      install.currentOrigin == .brew
      // Non-breaking spaces keep the command on one line when the text wraps.
      ? "Update it with “brew\u{00A0}upgrade\u{00A0}llama.cpp”, then restart Llama."
      : "Update it, then restart Llama."
    return "Your llama.cpp (\(version.tag)) may be too old for it. " + howTo
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
}
