import AppKit
import Foundation

/// Menu row for a downloadable model variant inside a family submenu.
final class VariantMenuItemView: NSView {
  private enum Font {
    static let primary = NSFont.systemFont(ofSize: 13)
    static let secondary = NSFont.systemFont(ofSize: 10, weight: .medium)
  }
  private let model: ModelCatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let statusIndicator = NSImageView()
  private let labelField = NSTextField(labelWithString: "")
  private let sizeLabel = NSTextField(labelWithString: "")
  private let progressLabel = NSTextField(labelWithString: "")
  private let backgroundView = NSView()

  private var trackingArea: NSTrackingArea?
  private var isHighlighted = false { didSet { updateHighlight() } }

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
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true
    statusIndicator.translatesAutoresizingMaskIntoConstraints = false
    statusIndicator.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.font = Font.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

    sizeLabel.font = Font.secondary
    sizeLabel.textColor = .secondaryLabelColor
    sizeLabel.lineBreakMode = .byTruncatingTail
    sizeLabel.translatesAutoresizingMaskIntoConstraints = false

    progressLabel.font = Font.secondary
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

    addSubview(backgroundView)
    backgroundView.addSubview(hStack)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      statusIndicator.widthAnchor.constraint(equalToConstant: 14),
      statusIndicator.heightAnchor.constraint(equalToConstant: 14),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 48),
      hStack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
      hStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
      hStack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 4),
      hStack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -4),
    ])
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    trackingArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
    addTrackingArea(trackingArea!)
  }

  override func mouseEntered(with event: NSEvent) { isHighlighted = true }
  override func mouseExited(with event: NSEvent) { isHighlighted = false }
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

  private func updateHighlight() {
    if isHighlighted {
      backgroundView.layer?.backgroundColor = NSColor.cgColor(.lbHoverBackground, in: backgroundView)
    } else {
      backgroundView.layer?.backgroundColor = NSColor.clear.cgColor
    }
    backgroundView.layer?.cornerRadius = 4
  }

  func refresh() {
    let status = modelManager.getModelStatus(model)
    let compatible = ModelCatalog.isModelCompatible(model)
    var title = "\(model.displayName)"
    if model.quantization == "Q8_0" { title += " (\(model.quantization))" }
    labelField.stringValue = title
    var secondary = "\(model.totalSize)"
    if model.supportsVision { secondary += " · 👓" }
    if model.supportsAudio { secondary += " · 🔊" }
    sizeLabel.stringValue = secondary
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
