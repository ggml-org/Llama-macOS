import AppKit
import Foundation

/// The model page's title line: the model name at page-title scale, bare and
/// flush left, with a live status dot beside it.
///
/// Deliberately not an identity block (no icon, no subtitle) -- every fuller
/// header treatment read as either a stray list row or an over-promoted hero.
/// The name is the one fact the title must carry; the icon's brand job is done
/// by the list, and the disk footprint lives on the Delete row where it
/// informs a decision. The dot keeps the one live signal worth keeping: green
/// while the model is running, dimmed while loading, absent when idle.
final class ModelPageHeaderView: ItemView {
  private let model: Model
  private unowned let server: LlamaServer

  private let titleLabel = Theme.primaryLabel()
  private let statusDot = NSView()

  /// Page-title scale for the model name -- a step up from the 13pt list rows
  /// so the header reads as a heading, not a stray list item.
  private static let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)

  init(
    model: Model,
    server: LlamaServer,
    showTags: Bool
  ) {
    self.model = model
    self.server = server
    super.init(frame: .zero)

    titleLabel.attributedStringValue = Format.modelName(
      id: model.id,
      color: Theme.Colors.textPrimary,
      hasVision: model.hasVisionSupport,
      showTags: showTags,
      font: Self.titleFont
    )
    titleLabel.maximumNumberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.cell?.truncatesLastVisibleLine = true
    titleLabel.allowsDefaultTighteningForTruncation = false

    setupLayout()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// A page header is static -- highlighting it would imply a dead click.
  override var highlightEnabled: Bool { false }

  private func setupLayout() {
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 3
    statusDot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      statusDot.widthAnchor.constraint(equalToConstant: 6),
      statusDot.heightAnchor.constraint(equalToConstant: 6),
    ])

    let row = NSStackView(views: [titleLabel, statusDot])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 6
    contentView.addSubview(row)
    row.pinToSuperview(top: 4, leading: 0, trailing: 0, bottom: 4)

    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  }

  /// Updates the status dot to the model's live server state: green while
  /// running, dimmed while loading, hidden when idle (the absence of a dot is
  /// the "not loaded" signal).
  func refresh() {
    let isActive = server.isActive(model: model)
    let isLoading = server.isLoading(model: model)
    statusDot.isHidden = !isActive && !isLoading
    restyleDot()
  }

  private func restyleDot() {
    let color: NSColor =
      server.isActive(model: model) ? .systemGreen : Theme.Colors.textTertiary
    statusDot.layer?.setBackgroundColor(color, in: self)
  }

  // The dot's layer color is a resolved CGColor; re-resolve on light/dark flips.
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyleDot()
  }
}
