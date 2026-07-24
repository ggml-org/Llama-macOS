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
  private let label: NSTextField
  private let title: String

  /// When non-nil, the row confirms inline instead of firing on first click:
  /// the first click arms it (swapping the label to `confirmTitle`), and only a
  /// second click within `confirmWindow` runs `onAction`. Disarms on hover-out
  /// or timeout, restoring the original title. Nil = fire immediately.
  private let confirmTitle: String?
  private var isArmed = false
  private var disarmWorkItem: DispatchWorkItem?
  private static let confirmWindow: TimeInterval = 3.0

  /// - Parameters:
  ///   - title: Row label, e.g. "Chat".
  ///   - symbol: SF symbol name for the leading glyph.
  ///   - destructive: Tints the whole row red for delete-style actions.
  ///   - detail: Optional trailing metadata (e.g. Delete's disk footprint).
  ///   - confirmTitle: When set, requires an inline two-step confirm (see above).
  ///   - onAction: Invoked on click (or the confirming second click).
  init(
    title: String,
    symbol: String,
    destructive: Bool = false,
    detail: String? = nil,
    confirmTitle: String? = nil,
    onAction: @escaping () -> Void
  ) {
    self.onAction = onAction
    self.symbol = symbol
    self.title = title
    self.confirmTitle = confirmTitle
    self.label = Theme.primaryLabel(title)
    super.init(frame: .zero)

    let color: NSColor = destructive ? .systemRed : Theme.Colors.modelIconTint
    Theme.configure(iconView, symbol: symbol, color: color, pointSize: 12)

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
    // No inline confirmation configured -- fire straight away.
    guard let confirmTitle else {
      onAction()
      return
    }
    // First click arms; second (confirming) click within the window fires.
    if isArmed {
      disarm()
      onAction()
    } else {
      arm(with: confirmTitle)
    }
  }

  /// Swaps the label to the confirm prompt and schedules an auto-disarm so a
  /// stray first click doesn't leave the row stuck in its armed state.
  private func arm(with confirmTitle: String) {
    isArmed = true
    label.stringValue = confirmTitle
    let workItem = DispatchWorkItem { [weak self] in self?.disarm() }
    disarmWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.confirmWindow, execute: workItem)
  }

  /// Restores the original label and cancels any pending auto-disarm.
  private func disarm() {
    disarmWorkItem?.cancel()
    disarmWorkItem = nil
    guard isArmed else { return }
    isArmed = false
    label.stringValue = title
  }

  /// Disarm when the pointer leaves the row -- moving away is an implicit cancel.
  override func highlightDidChange(_ highlighted: Bool) {
    super.highlightDidChange(highlighted)
    if !highlighted { disarm() }
  }
}
