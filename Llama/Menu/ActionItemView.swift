import AppKit

/// A labeled action row on a model page: leading SF symbol glyph + title,
/// styled like a regular menu item (hover highlight, full-row click target).
/// Used instead of bezel buttons, which read as dialog chrome inside a menu
/// and gray out whenever the app isn't frontmost (menu bar apps usually
/// aren't).
final class ActionItemView: ItemView {
  /// Settable so a row's action can reference the row itself (e.g. Copy model
  /// ID flashing its own confirmation) without a retain cycle at init.
  var onAction: () -> Void
  private let iconView = NSImageView()
  private let symbol: String

  /// - Parameters:
  ///   - title: Row label, e.g. "Chat".
  ///   - symbol: SF symbol name for the leading glyph.
  ///   - destructive: Tints the whole row red for delete-style actions.
  ///   - detail: Optional trailing metadata (e.g. Delete's disk footprint).
  ///   - onAction: Invoked on click.
  init(
    title: String,
    symbol: String,
    destructive: Bool = false,
    detail: String? = nil,
    onAction: @escaping () -> Void
  ) {
    self.onAction = onAction
    self.symbol = symbol
    super.init(frame: .zero)

    let color: NSColor = destructive ? .systemRed : Theme.Colors.modelIconTint
    Theme.configure(iconView, symbol: symbol, color: color, pointSize: 12)

    let label = Theme.primaryLabel(title)
    if destructive {
      label.textColor = .systemRed
    }

    // Fixed-width glyph slot so labels column-align across rows regardless of
    // each symbol's natural width.
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.widthAnchor.constraint(equalToConstant: 20).isActive = true

    let stack = NSStackView(views: [iconView, label])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 4

    // Trailing metadata in the dimmed secondary style, pushed to the far
    // edge -- context for the action, not part of its label.
    if let detail {
      stack.addArrangedSubview(.flexibleSpacer())
      let detailLabel = Theme.secondaryLabel(detail)
      detailLabel.textColor = Theme.Colors.textSecondary
      stack.addArrangedSubview(detailLabel)
    }
    contentView.addSubview(stack)
    stack.pinToSuperview()

    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: Layout.menuWidth),
      heightAnchor.constraint(equalToConstant: 28),
    ])

    addGesture(action: #selector(didClick))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Briefly swaps the glyph for a checkmark to confirm the action landed
  /// (used by Copy model ID). Restores the original symbol after a beat.
  func flashConfirmation() {
    Theme.configure(iconView, symbol: "checkmark", color: Theme.Colors.modelIconTint, pointSize: 12)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      guard let self else { return }
      Theme.configure(
        self.iconView, symbol: self.symbol, color: Theme.Colors.modelIconTint, pointSize: 12)
    }
  }

  @objc private func didClick() {
    onAction()
  }
}
