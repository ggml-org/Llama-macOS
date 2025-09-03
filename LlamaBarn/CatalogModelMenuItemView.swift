import AppKit
import Foundation

/// Custom view used for model catalog entries so selecting (download/cancel) does not dismiss the menu.
final class CatalogModelMenuItemView: NSView {
  private enum Font {
    static let primary = NSFont.systemFont(ofSize: 13)
    static let secondary = NSFont.systemFont(ofSize: 10, weight: .medium)
  }
  private let model: ModelCatalogEntry
  private unowned let modelManager: ModelManager
  private let membershipChanged: () -> Void

  private let statusIcon = NSImageView()
  private let labelField = NSTextField(labelWithString: "")
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

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 26) }

  private func setup() {
    wantsLayer = true
    backgroundView.translatesAutoresizingMaskIntoConstraints = false
    backgroundView.wantsLayer = true
    statusIcon.translatesAutoresizingMaskIntoConstraints = false
    statusIcon.symbolConfiguration = .init(pointSize: 12, weight: .regular)

    labelField.font = Font.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

    progressLabel.font = Font.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [statusIcon, labelField, progressLabel])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.spacing = 6
    stack.alignment = .centerY
    addSubview(backgroundView)
    backgroundView.addSubview(stack)

    NSLayoutConstraint.activate([
      backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      backgroundView.topAnchor.constraint(equalTo: topAnchor),
      backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
      statusIcon.widthAnchor.constraint(equalToConstant: 14),
      statusIcon.heightAnchor.constraint(equalToConstant: 14),
      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 48),
      stack.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -4),
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
    title += " - \(model.totalSize)"
    if model.supportsVision { title += " · 👓" }
    if model.supportsAudio { title += " · 🔊" }
    labelField.stringValue = title
    // Use semantic disabled text so dark mode contrast remains acceptable (alpha on secondaryLabelColor was too dim).
    labelField.textColor = compatible ? .labelColor : .tertiaryLabelColor

    progressLabel.stringValue = ""
    switch status {
    case .downloaded:
      statusIcon.image = NSImage(
        systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
      statusIcon.contentTintColor = .systemGreen
    case .downloading(let progress):
      let pct: Int
      if progress.totalUnitCount > 0 {
        pct = Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
      } else {
        pct = 0
      }
      statusIcon.image = NSImage(
        systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
      statusIcon.contentTintColor = .controlAccentColor
      progressLabel.stringValue = "\(pct)%"
    case .available:
      if compatible {
        statusIcon.image = NSImage(
          systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        statusIcon.contentTintColor = .secondaryLabelColor
      } else {
        statusIcon.image = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil)
        statusIcon.contentTintColor = .systemOrange
      }
    }
    needsDisplay = true
  }

}
