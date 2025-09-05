import AppKit
import Foundation

/// Menu row for a downloadable model variant inside a family submenu.
final class VariantMenuItemView: MenuRowView {
  private let model: ModelCatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let statusIndicator = NSImageView()
  private let labelField = NSTextField(labelWithString: "")
  private let sizeLabel = NSTextField(labelWithString: "")
  private let progressLabel = NSTextField(labelWithString: "")
  // Background handled by MenuRowView

  // Hover handling provided by MenuRowView

  init(
    model: ModelCatalogEntry, modelManager: ModelManager, membershipChanged: @escaping () -> Void
  ) {
    self.model = model
    self.modelManager = modelManager
    self.membershipChanged = membershipChanged
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 40) }

  private func setup() {
    wantsLayer = true
    statusIndicator.translatesAutoresizingMaskIntoConstraints = false
    statusIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.font = MenuTypography.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

    sizeLabel.font = MenuTypography.secondary
    sizeLabel.textColor = .secondaryLabelColor
    sizeLabel.lineBreakMode = .byTruncatingTail
    sizeLabel.translatesAutoresizingMaskIntoConstraints = false

    progressLabel.font = MenuTypography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    // Two-line text column (title + size/badges)
    let textColumn = NSStackView(views: [labelField, sizeLabel])
    textColumn.translatesAutoresizingMaskIntoConstraints = false
    textColumn.orientation = .vertical
    textColumn.alignment = .leading
    textColumn.spacing = 1

    // Leading group aligns status icon with first line of text
    let leading = NSStackView(views: [statusIndicator, textColumn])
    leading.translatesAutoresizingMaskIntoConstraints = false
    leading.orientation = .horizontal
    leading.alignment = .top
    leading.spacing = 6

    // Main horizontal row with flexible space and trailing progress
    let hStack = NSStackView(views: [leading, NSView(), progressLabel])
    hStack.translatesAutoresizingMaskIntoConstraints = false
    hStack.orientation = .horizontal
    hStack.spacing = 6
    hStack.alignment = .centerY

    contentView.addSubview(hStack)

    NSLayoutConstraint.activate([
      statusIndicator.widthAnchor.constraint(equalToConstant: MenuMetrics.smallIconSize),
      statusIndicator.heightAnchor.constraint(equalToConstant: MenuMetrics.smallIconSize),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.progressWidth),
      hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      hStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }
  override func mouseDown(with event: NSEvent) {
    handleAction()
    refresh()
  }

  private func handleAction() {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .available:
      if ModelCatalog.isModelCompatible(model) {
        modelManager.downloadModel(model)
        membershipChanged()
      }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged()
    case .downloaded:
      break
    }
  }

  // Hover highlight handled by base class

  func refresh() {
    let status = modelManager.getModelStatus(model)
    let compatible = ModelCatalog.isModelCompatible(model)
    var title = "\(model.displayName)"
    if model.quantization == "Q8_0" { title += " (\(model.quantization))" }
    labelField.stringValue = title
    sizeLabel.stringValue = model.totalSize
    // Use semantic disabled text so dark mode contrast remains acceptable (alpha on secondaryLabelColor was too dim).
    labelField.textColor = compatible ? .labelColor : .tertiaryLabelColor
    sizeLabel.textColor = compatible ? .secondaryLabelColor : .tertiaryLabelColor

    progressLabel.stringValue = ""
    switch status {
    case .downloaded:
      statusIndicator.image = NSImage(
        systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
      statusIndicator.contentTintColor = .systemGreen
    case .downloading(let progress):
      let pct: Int
      if progress.totalUnitCount > 0 {
        pct = Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
      } else {
        pct = 0
      }
      statusIndicator.image = NSImage(
        systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
      statusIndicator.contentTintColor = .controlAccentColor
      progressLabel.stringValue = "\(pct)%"
    case .available:
      if compatible {
        statusIndicator.image = NSImage(
          systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        statusIndicator.contentTintColor = .secondaryLabelColor
      } else {
        statusIndicator.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
        statusIndicator.contentTintColor = .systemOrange
      }
    }
    needsDisplay = true
  }

}
