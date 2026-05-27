import AppKit

/// Header row above the installed models list. Shows the "Installed" label
/// with a link to the running server's /models endpoint.
final class InstalledHeaderView: ItemView {
  private var linkUrl: URL?
  private let linkLabel = Theme.secondaryLabel()

  init(linkText: String?, linkUrl: URL?) {
    self.linkUrl = linkUrl
    super.init(frame: .zero)

    let titleLabel = Theme.secondaryLabel()
    titleLabel.textColor = Theme.Colors.textPrimary
    titleLabel.stringValue = "Installed"
    titleLabel.maximumNumberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.cell?.truncatesLastVisibleLine = true
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let titleRow: NSView
    if let linkText, linkUrl != nil {
      linkLabel.attributedStringValue = NSAttributedString(
        string: linkText,
        attributes: [
          .foregroundColor: NSColor.linkColor,
          .font: Theme.Fonts.secondary,
        ])
      linkLabel.isSelectable = false
      let click = NSClickGestureRecognizer(target: self, action: #selector(openLink))
      linkLabel.addGestureRecognizer(click)

      let row = NSStackView(views: [titleLabel, linkLabel])
      row.orientation = .horizontal
      row.spacing = 4
      row.alignment = .firstBaseline
      titleRow = row
    } else {
      titleRow = titleLabel
    }

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let rootStack = NSStackView(views: [titleRow, spacer])
    rootStack.orientation = .horizontal
    rootStack.alignment = .centerY
    rootStack.spacing = 6

    contentView.addSubview(rootStack)
    rootStack.pinToSuperview()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { false }

  @objc private func openLink() {
    if let linkUrl {
      NSWorkspace.shared.open(linkUrl)
    }
  }
}
