import AppKit
import Foundation

/// Container view for expanded model details.
/// Shows a compact row of context tier pills. Selecting a tier updates user
/// preferences and reloads the server if running.
final class ExpandedModelDetailsView: ItemView {
  private let model: Model
  private unowned let server: LlamaServer

  // Tiers backing the picker, in the order they appear (index = segment).
  private var tiers: [ContextTier] = []
  // Tiers actually runnable on this device; the rest render disabled.
  private var enabledTiers: Set<ContextTier> = []
  // One pill per tier, same order as `tiers`. Each is a label wrapped in a
  // padded container whose layer draws the selection background.
  private var segments: [(container: NSView, label: NSTextField)] = []
  // Hairline dividers between adjacent pills; divider[i] sits between
  // segments i and i+1. Hidden when adjacent to the selected pill.
  private var dividers: [NSView] = []
  // Index of the currently selected tier in `tiers`.
  private var selectedIdx = 0
  // The pill row container -- outlined to give the picker a defined shape.
  private var picker: NSStackView?

  init(
    model: Model,
    server: LlamaServer
  ) {
    self.model = model
    self.server = server
    super.init(frame: .zero)
    setupLayout()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // Disable hover highlight since this is an info container
  override var highlightEnabled: Bool { false }

  private func setupLayout() {
    // Main vertical stack for indented rows
    let mainStack = NSStackView()
    mainStack.orientation = .vertical
    mainStack.alignment = .leading
    mainStack.spacing = 4

    // For sideloaded models awaiting their MemProfile, show a placeholder message
    // instead of the picker (we don't have accurate memory estimates yet).
    // For failed estimation (-1), show a failure message with the 4k fallback.
    if model.ctxBytesPer1kTokens == 0 {
      let estimatingLabel = Theme.secondaryLabel()
      estimatingLabel.stringValue = "Estimating memory requirements..."
      estimatingLabel.textColor = Theme.Colors.textSecondary
      mainStack.addArrangedSubview(estimatingLabel)
    } else if model.ctxBytesPer1kTokens < 0 {
      let failedLabel = Theme.secondaryLabel()
      failedLabel.stringValue = "Could not estimate memory — using 4k context"
      failedLabel.textColor = Theme.Colors.textSecondary
      failedLabel.maximumNumberOfLines = 1
      failedLabel.lineBreakMode = .byTruncatingTail
      mainStack.addArrangedSubview(failedLabel)
    } else {
      // A "Context length" header with the tier pills below. The memory usage
      // for the selected tier lives on the model row's metadata line ("3.3 GB
      // mem"), which refreshes via LBUserSettingsDidChange when a tier is
      // picked -- so the expanded details stay two compact lines. Pills are
      // custom-drawn instead of NSSegmentedControl: lighter visually, and
      // immune to the inactive-window graying AppKit applies to standard
      // controls when the app isn't frontmost (menu bar apps usually aren't,
      // so the segmented control's thumb rendered gray instead of
      // accent-colored).
      // Show every tier the model natively supports; the ones this device
      // can't fit in memory render disabled so the model's full range is
      // still visible.
      tiers = model.displayContextTiers
      enabledTiers = Set(model.supportedContextTiers)
      // Fall back to the first supported tier if no effective tier is resolved.
      let effectiveTier = model.effectiveCtxTier ?? tiers.first ?? .k4
      selectedIdx = tiers.firstIndex(of: effectiveTier) ?? 0

      let picker = NSStackView()
      picker.orientation = .horizontal
      // 1px gap on either side of each divider so the selected pill's
      // background reaches almost to the neighboring dividers.
      picker.spacing = 1
      // Subtle outline around the whole row to give the picker a defined shape.
      picker.wantsLayer = true
      picker.layer?.borderWidth = 1
      picker.layer?.cornerRadius = 6
      // 2px insets all around so the selected pill's background keeps the
      // same breathing room from the outline at the ends as it does
      // vertically.
      picker.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
      // Hug the pills tightly -- otherwise the stack stretches to the menu
      // width and the outline trails off past the last pill.
      picker.setHuggingPriority(.required, for: .horizontal)
      picker.setContentHuggingPriority(.required, for: .horizontal)
      self.picker = picker
      for (idx, tier) in tiers.enumerated() {
        if idx > 0 {
          picker.addArrangedSubview(makeDivider())
        }
        let segment = makeSegment(label: tier.shortLabel)
        // Explain why a disabled tier can't be selected (memory constraint).
        if !enabledTiers.contains(tier) {
          segment.toolTip = model.incompatibilitySummary(
            ctxWindowTokens: Double(tier.rawValue))
        }
        picker.addArrangedSubview(segment)
      }
      restyleSegments()

      let header = Theme.secondaryLabel("Context length")
      header.textColor = Theme.Colors.modelIconTint
      mainStack.addArrangedSubview(header)
      mainStack.addArrangedSubview(picker)
    }

    // "Chat with this model" link -- opens the webui with this model
    // preselected. Sits below whatever the branch above added (picker or a
    // status message), with a bit of extra breathing room above it.
    if let last = mainStack.arrangedSubviews.last {
      mainStack.setCustomSpacing(8, after: last)
    }
    mainStack.addArrangedSubview(makeChatLink())

    // Add indent wrapper to align with model text
    let indent = NSView()
    indent.translatesAutoresizingMaskIntoConstraints = false
    indent.widthAnchor.constraint(equalToConstant: Layout.expandedIndent).isActive = true

    let indentedRow = NSStackView(views: [indent, mainStack])
    indentedRow.orientation = .horizontal
    indentedRow.alignment = .top
    indentedRow.spacing = 0

    contentView.addSubview(indentedRow)
    indentedRow.pinToSuperview(top: 2, leading: 0, trailing: 0, bottom: 2)

    // Pin to the standard menu width so a long label (e.g. the "Could not estimate
    // memory" fallback) can't widen the whole menu beyond what model rows use.
    widthAnchor.constraint(equalToConstant: Layout.menuWidth).isActive = true
  }

  // MARK: - Chat Link

  /// Builds the "Chat with this model" link. Styled like the menu's other
  /// inline links (e.g. the header's WebUI link) and wired to open the webui.
  private func makeChatLink() -> NSView {
    let label = Theme.secondaryLabel()
    label.attributedStringValue = NSAttributedString(
      string: "Chat with this model",
      attributes: [
        .foregroundColor: NSColor.linkColor,
        .font: Theme.Fonts.secondary,
      ]
    )
    label.isSelectable = false
    let click = NSClickGestureRecognizer(target: self, action: #selector(didClickChat))
    label.addGestureRecognizer(click)
    return label
  }

  /// Webui URL for this model: the server root with the model preselected via
  /// the `?model=` query param the webui reads. Uses the resolved host so a
  /// custom network bind address (incl. 0.0.0.0 -> local IP) still works.
  private var chatUrl: URL? {
    var components = URLComponents()
    components.scheme = "http"
    components.host = LlamaServer.resolvedHost
    components.port = LlamaServer.port
    components.path = "/"
    components.queryItems = [URLQueryItem(name: "model", value: model.id)]
    return components.url
  }

  @objc private func didClickChat() {
    // The server runs continuously in router mode (started at app launch), so we
    // just open the webui -- no need to start or wait on anything. In router mode
    // `serve` loads the model on demand from the `?model=` selection when the
    // user sends their first message.
    guard let url = chatUrl else { return }
    openInBrowser(url)
  }

  // MARK: - Tier Picker

  /// Creates one clickable pill for the picker: a label with a little padding
  /// in a rounded-corner container that draws the selection background.
  private func makeSegment(label text: String) -> NSView {
    let label = Theme.secondaryLabel(text)
    let container = NSView()
    container.wantsLayer = true
    container.layer?.cornerRadius = 4
    container.translatesAutoresizingMaskIntoConstraints = false
    label.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
      label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
      label.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
      label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1),
    ])

    let click = NSClickGestureRecognizer(target: self, action: #selector(didClickSegment(_:)))
    container.addGestureRecognizer(click)
    segments.append((container, label))
    return container
  }

  /// Creates a hairline divider that visually splits the gap between two
  /// unselected pills (the gap otherwise reads as double the edge padding).
  private func makeDivider() -> NSView {
    let divider = NSView()
    divider.wantsLayer = true
    divider.translatesAutoresizingMaskIntoConstraints = false
    divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
    divider.heightAnchor.constraint(equalToConstant: 8).isActive = true
    dividers.append(divider)
    return divider
  }

  /// Applies selected/unselected styling to every pill: the selected tier gets
  /// a subtle background and primary text, the rest plain secondary text.
  /// Also recolors the dividers, hiding those adjacent to the selection.
  private func restyleSegments() {
    picker?.layer?.setBorderColor(Theme.Colors.separator, in: self)
    for (idx, segment) in segments.enumerated() {
      let selected = idx == selectedIdx
      let enabled = enabledTiers.contains(tiers[idx])
      // Disabled tiers use the faint tertiary gray; enabled-but-unselected
      // ones use the darker icon tint (not textSecondary -- it's too close to
      // tertiary for the available/unavailable distinction to read).
      segment.label.textColor =
        !enabled
        ? Theme.Colors.textTertiary
        : selected ? Theme.Colors.textPrimary : Theme.Colors.modelIconTint
      segment.container.layer?.setBackgroundColor(
        selected ? Theme.Colors.subtleBackground : .clear, in: self)
    }
    // Hide (via clear color, to keep layout stable) the dividers touching the
    // selected pill -- its background already delimits those gaps.
    for (idx, divider) in dividers.enumerated() {
      let adjacentToSelection = idx == selectedIdx || idx + 1 == selectedIdx
      divider.layer?.setBackgroundColor(
        adjacentToSelection ? .clear : Theme.Colors.separator, in: self)
    }
  }

  // Layer colors are resolved CGColors, so re-resolve them when the system
  // appearance flips between light and dark.
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    restyleSegments()
  }

  // MARK: - Actions

  @objc private func didClickSegment(_ sender: NSClickGestureRecognizer) {
    guard let container = sender.view,
      let idx = segments.firstIndex(where: { $0.container == container })
    else { return }
    let tier = tiers[idx]

    // Ignore clicks on tiers this device can't run.
    guard enabledTiers.contains(tier) else { return }

    // Reflect the new selection in the picker right away. (The model row's
    // "N GB mem" metadata refreshes via the settings-change notification.)
    selectedIdx = idx
    restyleSegments()

    // Skip the rest if this is already the active tier.
    guard tier != model.effectiveCtxTier else { return }

    // Save the new preference
    UserSettings.setSelectedCtxTier(tier, for: model.id)

    // Regenerate models.ini and reload server
    ModelManager.shared.updateModelsFile()

    // If this model is running, restart the server to apply the new context size
    if server.isActive(model: model) {
      server.reload()
    }
  }

}
