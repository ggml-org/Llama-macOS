import AppKit
import Foundation

/// Menu row representing a single installed model.
/// Visual states:
/// - Idle: circular icon (inactive) + label
/// - Loading: circular icon (active)
/// - Running: circular icon (active)
final class InstalledModelMenuItemView: MenuRowView {
  private let model: ModelCatalogEntry
  private unowned let server: LlamaServer
  private unowned let modelManager: ModelManager
  private let membershipChanged: (ModelCatalogEntry) -> Void

  private static let iconBaselineYOffset: CGFloat = -2

  // Subviews
  private let circleIcon = CircularIconView()
  private let labelField = NSTextField(labelWithString: "")
  private let progressLabel = NSTextField(labelWithString: "")
  // Second-line label: used for progress during downloads and for
  // consistent two-line layout (size/badges) when idle/running.
  private let infoRow = NSStackView()
  private let sizeLabel = NSTextField(labelWithString: "")
  private let separatorLabel = CenteredDotSeparatorView()
  private let ctxLabel = NSTextField(labelWithString: "")
  private let memorySeparatorLabel = CenteredDotSeparatorView()
  private let memoryLabel = NSTextField(labelWithString: "")
  private let cancelImageView = NSImageView()
  private let deleteButton = NSButton()

  // Hover handling is provided by MenuRowView
  private var rowClickRecognizer: NSClickGestureRecognizer?

  init(
    model: ModelCatalogEntry, server: LlamaServer, modelManager: ModelManager,
    membershipChanged: @escaping (ModelCatalogEntry) -> Void
  ) {
    self.model = model
    self.server = server
    self.modelManager = modelManager
    self.membershipChanged = membershipChanged
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
    refresh()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 260, height: 40) }

  private func setup() {
    wantsLayer = true
    circleIcon.setImage(NSImage(named: model.icon))

    labelField.stringValue = model.displayName
    labelField.font = Typography.primary
    labelField.lineBreakMode = .byTruncatingTail
    labelField.translatesAutoresizingMaskIntoConstraints = false

    progressLabel.font = Typography.secondary
    progressLabel.textColor = .secondaryLabelColor
    progressLabel.alignment = .right
    progressLabel.translatesAutoresizingMaskIntoConstraints = false

    if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel download") {
      img.isTemplate = true
      cancelImageView.image = img
    }
    cancelImageView.translatesAutoresizingMaskIntoConstraints = false
    cancelImageView.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    cancelImageView.imageScaling = .scaleProportionallyDown
    cancelImageView.contentTintColor = .systemRed
    cancelImageView.isHidden = true

    deleteButton.translatesAutoresizingMaskIntoConstraints = false
    deleteButton.isBordered = false
    deleteButton.imagePosition = .imageOnly
    deleteButton.setButtonType(.momentaryChange)
    deleteButton.title = ""
    deleteButton.toolTip = "Delete"
    deleteButton.setAccessibilityLabel("Delete")
    if let img = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") {
      img.isTemplate = true
      deleteButton.image = img
    }
    deleteButton.contentTintColor = .secondaryLabelColor
    deleteButton.isHidden = true
    deleteButton.target = self
    deleteButton.action = #selector(performDelete)

    let labels = [sizeLabel, ctxLabel, memoryLabel]
    for label in labels {
      label.font = Typography.secondary
      label.textColor = .secondaryLabelColor
      label.lineBreakMode = .byTruncatingTail
      label.translatesAutoresizingMaskIntoConstraints = false
    }

    infoRow.orientation = .horizontal
    infoRow.spacing = 4
    infoRow.alignment = .centerY
    infoRow.translatesAutoresizingMaskIntoConstraints = false
    infoRow.addArrangedSubview(sizeLabel)
    infoRow.addArrangedSubview(separatorLabel)
    infoRow.addArrangedSubview(ctxLabel)
    infoRow.addArrangedSubview(memorySeparatorLabel)
    infoRow.addArrangedSubview(memoryLabel)

    // Order: icon | (label over bytes) | spacer | (state, progress, delete, action)
    // Spacer expands so trailing visuals sit flush right.
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    labelField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    labelField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    progressLabel.setContentHuggingPriority(.required, for: .horizontal)
    progressLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    // Left: icon aligned with first text line, then two-line text column
    let nameStack = NSStackView(views: [labelField, infoRow])
    nameStack.translatesAutoresizingMaskIntoConstraints = false
    nameStack.orientation = .vertical
    nameStack.spacing = 1
    nameStack.alignment = .leading

    let leading = NSStackView(views: [circleIcon, nameStack])
    leading.translatesAutoresizingMaskIntoConstraints = false
    leading.orientation = .horizontal
    // Vertically center the circular icon relative to the two-line text, like Wi‑Fi menu
    leading.alignment = .centerY
    leading.spacing = 6

    // Right: status/progress/delete/action in a row
    cancelImageView.setContentHuggingPriority(.required, for: .horizontal)
    cancelImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

    let rightStack = NSStackView(views: [progressLabel, cancelImageView, deleteButton])
    rightStack.translatesAutoresizingMaskIntoConstraints = false
    rightStack.orientation = .horizontal
    rightStack.spacing = 6
    rightStack.alignment = .centerY

    let rootStack = NSStackView(views: [leading, spacer, rightStack])
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    rootStack.orientation = .horizontal
    rootStack.spacing = 6
    rootStack.alignment = .centerY
    contentView.addSubview(rootStack)

    NSLayoutConstraint.activate([
      circleIcon.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      circleIcon.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      cancelImageView.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      cancelImageView.heightAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.iconSize),
      deleteButton.widthAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),
      deleteButton.heightAnchor.constraint(equalToConstant: MenuMetrics.iconBadgeSize),

      progressLabel.widthAnchor.constraint(lessThanOrEqualToConstant: MenuMetrics.progressWidth),
      rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      // Pin trailing controls to the backgroundView’s edge (hover highlight),
      // not the contentView’s inner padding, so the trash icon visually
      // reaches the end of the item.
      // Respect the item’s standard inner padding so the trash aligns
      // consistently with other rows.
      rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
      rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
  }

  // Row click recognizer to toggle, letting the delete button handle its own action.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if rowClickRecognizer == nil {
      let click = NSClickGestureRecognizer(target: self, action: #selector(didClickRow))
      addGestureRecognizer(click)
      rowClickRecognizer = click
    }
  }

  @objc private func didClickRow() { toggle() }

  private func toggle() {
    let status = modelManager.getModelStatus(model)
    switch status {
    case .downloaded:
      if server.isActive(model: model) { server.stop() } else { server.start(model: model) }
    case .downloading:
      modelManager.cancelModelDownload(model)
      membershipChanged(model)
    case .available:
      break
    }
    refresh()
  }

  override func hoverHighlightDidChange(_ highlighted: Bool) {
    let status = modelManager.getModelStatus(model)
    // Show delete button only when hovering over a downloaded model
    deleteButton.isHidden = !(highlighted && status == .downloaded)
    // Update icon tint when highlight changes.
    applyIconTint()
  }

  func refresh() {
    // Determine state
    let status = modelManager.getModelStatus(model)
    let isActive = server.isActive(model: model)
    let isLoadingServer = isActive && server.isLoading
    let isRunning = isActive && server.isRunning
    let recommendedContext = ModelCatalog.recommendedContextLength(for: model)
    // Reset trailing visuals before applying current status
    cancelImageView.isHidden = true

    // Spinner is now displayed inside the circular icon instead of the right side.
    circleIcon.setLoading(isLoadingServer)

    let sizeText = model.totalSize
    let contextText: String = {
      if let recommendedContext {
        return TokenFormatters.shortTokens(recommendedContext)
      }
      return ""
    }()
    let memoryText: String? = {
      if isRunning {
        let memMB = server.memoryUsageMB
        if memMB <= 0 { return nil }
        if memMB >= 1024 {
          let gb = memMB / 1024
          let gbText = gb < 10 ? String(format: "%.1f", gb) : String(format: "%.0f", gb)
          return "\(gbText) GB"
        } else {
          return String(format: "%.0f MB", memMB)
        }
      }
      return nil
    }()

    // Download progress / action area
    switch status {
    case .downloading(let progress):
      cancelImageView.isHidden = false
      let percent: Int
      if progress.totalUnitCount > 0 {
        percent = Int(Double(progress.completedUnitCount) / Double(progress.totalUnitCount) * 100)
      } else {
        percent = 0
      }
      progressLabel.stringValue = "\(percent)%"
      // Second line: always show downloaded/total in GB with two decimals.
      // When the network hasn't reported a total yet (0), fall back to catalog size.
      let completedText = ByteFormatters.gbTwoDecimals(progress.completedUnitCount)
      let totalBytes: Int64 = {
        if progress.totalUnitCount > 0 {
          return progress.totalUnitCount
        } else {
          // fileSize is our catalog estimate for the full model (all parts).
          return model.fileSize
        }
      }()
      let totalText = ByteFormatters.gbTwoDecimals(totalBytes)
      sizeLabel.attributedStringValue = IconLabelFormatter.make(
        icon: IconLabelFormatter.sizeSymbol,
        text: "\(completedText) / \(totalText)",
        color: .secondaryLabelColor,
        baselineOffset: Self.iconBaselineYOffset
      )
      ctxLabel.stringValue = ""
      ctxLabel.isHidden = true
      memoryLabel.stringValue = ""
      memoryLabel.isHidden = true
      memorySeparatorLabel.isHidden = true
      separatorLabel.isHidden = true
      infoRow.isHidden = false
    // Removed indicator image in favor of simplified state display
    case .downloaded, .available:
      progressLabel.stringValue = ""
      infoRow.isHidden = false

      sizeLabel.attributedStringValue = IconLabelFormatter.make(
        icon: IconLabelFormatter.sizeSymbol,
        text: sizeText,
        color: .secondaryLabelColor,
        baselineOffset: Self.iconBaselineYOffset
      )
      if contextText.isEmpty {
        ctxLabel.isHidden = true
        separatorLabel.isHidden = true
      } else {
        ctxLabel.attributedStringValue = IconLabelFormatter.make(
          icon: IconLabelFormatter.contextSymbol,
          text: contextText,
          color: .secondaryLabelColor,
          baselineOffset: Self.iconBaselineYOffset
        )
        ctxLabel.isHidden = false
        separatorLabel.isHidden = false
      }

      if let memoryText {
        memoryLabel.attributedStringValue = IconLabelFormatter.make(
          icon: IconLabelFormatter.memorySymbol,
          text: memoryText,
          color: .secondaryLabelColor,
          baselineOffset: Self.iconBaselineYOffset
        )
        memoryLabel.isHidden = false
        memorySeparatorLabel.isHidden = false
      } else {
        memoryLabel.stringValue = ""
        memoryLabel.isHidden = true
        memorySeparatorLabel.isHidden = true
      }
    }
    // Update leading circular badge state and tinting
    // Icon should become blue only after the model is done loading (running)
    circleIcon.isActive = isRunning
    applyIconTint(isActive: isRunning)
    needsDisplay = true
  }

  /// Installed model icons use the primary label tint unless the server is running,
  /// in which case the circular badge handles the white active glyph.
  private func applyIconTint(isActive: Bool? = nil) {
    let statusIsActive: Bool
    if let isActive = isActive {
      statusIsActive = isActive
    } else {
      let isActiveModel = server.isActive(model: model)
      // Consider active (blue) only when the server is running
      statusIsActive = isActiveModel && server.isRunning
    }
    // When active, circular view sets white tint; only tweak in inactive state.
    if !statusIsActive {
      circleIcon.imageView.contentTintColor = .labelColor
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    cancelImageView.contentTintColor = .systemRed
    deleteButton.contentTintColor = .secondaryLabelColor
  }

  @objc private func performDelete() {
    let status = modelManager.getModelStatus(model)
    guard case .downloaded = status else { return }
    modelManager.deleteDownloadedModel(model)
    membershipChanged(model)
  }

  private func performStop() {
    let isActive = server.isActive(model: model)
    guard isActive else { return }
    server.stop()
    refresh()
  }

  private func performReveal() {
    let url = URL(fileURLWithPath: model.modelFilePath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

}
