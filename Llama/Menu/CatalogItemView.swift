import AppKit

/// A single suggestion row in the Discover section. Lighter than `ModelItemView`:
/// a catalog suggestion isn't a resolved `Model` yet (no download URL, no
/// MemProfile), so it carries no live status — it's purely an invitation to
/// install. Clicking the row (or the download glyph) kicks off the same
/// resolve-and-install flow a deeplink would.
final class CatalogItemView: ItemView {
  private let suggestion: Catalog.Suggestion
  private let onInstall: (Catalog.Suggestion) -> Void

  private let iconView = IconView()
  private let titleLabel = Theme.primaryLabel()
  private let subtitleLabel = Theme.tertiaryLabel()
  private let installImageView = NSImageView()

  /// Subtitle: just the download size, e.g. "2.5 GB". Line two is for the
  /// model's properties (size); the quant — which says *which* build this is —
  /// belongs on line one next to the name (see `titleText`).
  private var subtitleText: String { suggestion.sizeLabel ?? "" }

  /// Title: the parsed view of the id the suggestion resolves to — the same
  /// rendering the installed row uses, so the row looks identical before and
  /// after installing: same name, same chips.
  private var titleText: NSAttributedString {
    // Build the would-be id (repo + quant when known) and reuse the installed
    // row's formatter so both sections get identical treatment.
    let id = suggestion.quant.map { Model.makeId(orgSlashRepo: suggestion.repo, tag: $0) }
      ?? suggestion.repo
    return Format.modelName(
      id: id, color: Theme.Colors.textPrimary, hasVision: suggestion.hasVision)
  }

  init(suggestion: Catalog.Suggestion, onInstall: @escaping (Catalog.Suggestion) -> Void) {
    self.suggestion = suggestion
    self.onInstall = onInstall
    super.init(frame: .zero)

    iconView.imageView.image =
      suggestion.brandLogoAsset.flatMap { NSImage(named: $0) }
      ?? NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "Model")
    iconView.inactiveTintColor = Theme.Colors.modelIconTint

    Theme.configure(
      installImageView, symbol: "arrow.down", tooltip: "Install model",
      color: .tertiaryLabelColor)

    titleLabel.attributedStringValue = titleText
    // Raw repo as tooltip, matching the installed row's raw-id tooltip.
    titleLabel.toolTip = suggestion.repo
    titleLabel.maximumNumberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail

    subtitleLabel.stringValue = subtitleText
    subtitleLabel.maximumNumberOfLines = 1
    subtitleLabel.lineBreakMode = .byTruncatingTail

    setupLayout()
    addGesture(action: #selector(didClickRow))
    let installClick = NSClickGestureRecognizer(target: self, action: #selector(didClickInstall))
    installImageView.addGestureRecognizer(installClick)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setupLayout() {
    let textColumn = NSStackView(views: [titleLabel, subtitleLabel])
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = Layout.textLineSpacing

    let leading = NSStackView(views: [iconView, textColumn])
    leading.orientation = .horizontal
    leading.alignment = .centerY
    leading.spacing = 6

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let rootStack = NSStackView(views: [leading, spacer, installImageView])
    rootStack.orientation = .horizontal
    rootStack.alignment = .centerY
    rootStack.spacing = 6

    contentView.addSubview(rootStack)
    rootStack.pinToSuperview()

    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Layout.menuWidth),
      heightAnchor.constraint(equalToConstant: 40),
    ])
    Layout.constrainToIconSize(installImageView)
    installImageView.setContentHuggingPriority(.required, for: .horizontal)
    installImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  }

  /// ⌘-click opens the suggestion's repo on Hugging Face instead of installing.
  /// Deliberately undiscoverable for now -- a lightweight way to vet a
  /// recommendation while we decide whether the link deserves real UI.
  @objc private func didClickRow() {
    if NSEvent.modifierFlags.contains(.command),
      let url = URL(string: "https://huggingface.co/\(suggestion.repo)")
    {
      openInBrowser(url)
      return
    }
    onInstall(suggestion)
  }

  @objc private func didClickInstall() { onInstall(suggestion) }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    installImageView.contentTintColor = .tertiaryLabelColor
  }
}
