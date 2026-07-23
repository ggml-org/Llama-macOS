import AppKit
import Foundation

/// Static identity at the top of a model page: the model's icon and title.
///
/// This is deliberately not a `ModelItemView`: a page header does not navigate
/// when clicked and should not inherit the list row's hover background or hidden
/// actions. The model's live loading state still appears in its icon. Page
/// actions live in the `ActionItemView` rows below the settings.
final class ModelPageHeaderView: ItemView {
  private let model: Model
  private unowned let server: LlamaServer

  private let iconView = IconView()
  private let titleLabel = Theme.primaryLabel()
  private let subtitleLabel = Theme.secondaryLabel()

  init(
    model: Model,
    server: LlamaServer,
    showTags: Bool
  ) {
    self.model = model
    self.server = server
    super.init(frame: .zero)

    iconView.imageView.image =
      model.brandLogoAsset.flatMap { NSImage(named: $0) }
      ?? NSImage(systemSymbolName: "cube.fill", accessibilityDescription: "Model")

    titleLabel.attributedStringValue = Format.modelName(
      id: model.id,
      color: Theme.Colors.textPrimary,
      hasVision: model.hasVisionSupport,
      showTags: showTags
    )
    titleLabel.maximumNumberOfLines = 1
    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.cell?.truncatesLastVisibleLine = true
    titleLabel.allowsDefaultTighteningForTruncation = false

    // Disk footprint, dropped from the list row's subtitle when the page
    // header went identity-only. (Context length is deliberately absent --
    // the picker below owns that story, including memory cost.)
    subtitleLabel.stringValue = "\(model.totalSize) on disk"
    subtitleLabel.textColor = Theme.Colors.textSecondary

    setupLayout()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// A page header is static -- highlighting it would imply a dead click.
  override var highlightEnabled: Bool { false }

  private func setupLayout() {
    // Two-line text column mirroring the list rows: title over metadata.
    let textColumn = NSStackView(views: [titleLabel, subtitleLabel])
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = Layout.textLineSpacing

    let identityRow = NSStackView(views: [iconView, textColumn])
    identityRow.orientation = .horizontal
    identityRow.alignment = .centerY
    identityRow.spacing = 6
    contentView.addSubview(identityRow)
    identityRow.pinToSuperview(top: 4, leading: 0, trailing: 0, bottom: 4)

    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  }

  /// Updates the status icon to reflect the model's live server state.
  func refresh() {
    iconView.inactiveTintColor = Theme.Colors.modelIconTint
    iconView.setLoading(server.isLoading(model: model))
    iconView.isActive = server.isActive(model: model)
  }
}
