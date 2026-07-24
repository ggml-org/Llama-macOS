import AppKit
import Foundation

/// Controls the status bar item and its AppKit menu.
/// Breaks menu construction into section helpers so each concern stays focused.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: ModelManager
  private let server: LlamaServer
  private var actionHandler: ModelActionHandler!

  // Section State
  /// The installed model whose detail page is currently replacing the list.
  /// Reset when the menu closes, so every fresh open starts at the model list.
  private var selectedModelId: String?

  /// Whether the Installed list is showing all rows vs. the collapsed first few.
  /// Reset on menu close so each open starts collapsed.
  private var isInstalledListExpanded = false

  /// Web catalog the Discover "Browse models" link points at — more models live
  /// here. Matches the empty-state browse link.
  private static let browseCatalogUrl = URL(string: "https://llama.app/models")!

  /// Featured catalog suggestions for the Discover section. Fetched from the
  /// remote catalog on launch (and on menu-open if still empty); empty when the
  /// fetch hasn't landed or failed, in which case the section simply doesn't show.
  private var discoverSuggestions: [Catalog.Suggestion] = []
  private var isLoadingDiscover = false

  /// Set of managed model ids reflected in the menu as last built. Lets the
  /// progress observer distinguish a membership change (a download started or
  /// stopped — needs a full rebuild so rows appear/disappear) from a plain
  /// progress tick (just refresh the existing rows). Without this, a download
  /// kicked off from Discover wouldn't surface as a row until the next rebuild.
  private var renderedManagedIds: Set<String> = []

  private var hintPopover: HintPopover?

  /// A download has finished that the user hasn't seen yet (i.e. hasn't opened
  /// the menu since). Drives the checkmark badge on the icon; cleared the next
  /// time the menu opens. In-memory only -- downloads run only while the app is
  /// up, so there's nothing to persist.
  private var hasUnseenCompletion = false

  /// Whether the menu is currently open. Lets us treat a completion the user is
  /// already watching live as "seen", and drives the clear-on-open behaviour.
  private var isMenuOpen = false

  /// The (badge, dim) pair last applied to the status button, so the frequent
  /// `refresh()` calls during a download don't rebuild an identical icon image
  /// on every progress tick.
  private var appliedIcon: (symbol: String?, dim: CGFloat)?

  // Store observer tokens for proper cleanup
  private var observers: [NSObjectProtocol] = []

  init(modelManager: ModelManager? = nil, server: LlamaServer? = nil) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager ?? .shared
    self.server = server ?? .shared
    super.init()

    self.actionHandler = ModelActionHandler(
      modelManager: self.modelManager,
      server: self.server,
      onMembershipChange: { [weak self] _ in
        self?.rebuildMenuIfPossible()
        self?.refresh()
      }
    )

    configureStatusItem()
    setupObservers()
    showWelcomeIfNeeded()
    loadDiscoverSuggestions()
  }

  /// Fetches featured catalog suggestions in the background, then rebuilds the
  /// menu so the Discover section appears. No-op if a fetch is already in flight.
  private func loadDiscoverSuggestions() {
    guard !isLoadingDiscover else { return }
    isLoadingDiscover = true
    let systemMemoryMb = SystemMemory.memoryMb
    Task { [weak self] in
      let suggestions = await Catalog.fetchFeatured(systemMemoryMb: systemMemoryMb)
      await MainActor.run {
        guard let self else { return }
        self.isLoadingDiscover = false
        self.discoverSuggestions = suggestions
        self.rebuildMenuIfPossible()
      }
    }
  }

  func openMenu() {
    statusItem.button?.performClick(nil)
  }

  private func showWelcomeIfNeeded() {
    guard !UserSettings.hasSeenWelcome else { return }

    // Show after a short delay to ensure the status item is visible
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self else { return }
      self.showHint("Hello, I'm Llama")
      UserSettings.hasSeenWelcome = true
    }
  }

  /// Shows a short speech-bubble message anchored to the menu bar icon.
  /// Replaces any currently visible hint.
  func showHint(_ message: String) {
    let popover = HintPopover(message: message)
    popover.show(from: statusItem)
    hintPopover = popover
  }

  private func configureStatusItem() {
    updateStatusIcon()

    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    statusItem.menu = menu
  }

  /// Icon opacity for the current server state: full when a model is loaded, mid
  /// while loading, dim when idle.
  private var statusIconDimAlpha: CGFloat {
    if server.isAnyModelLoaded { return 1.0 }
    if server.isAnyModelLoading { return 0.7 }
    return 0.4
  }

  /// The SF Symbol to badge the icon with, or nil for a plain icon. Live download
  /// activity takes precedence over an unseen completion -- while anything is
  /// downloading we show the down-arrow; once it all settles, a checkmark flags a
  /// completion the user hasn't seen yet.
  private var statusBadgeSymbol: String? {
    if !modelManager.downloadingModels.isEmpty { return "arrow.down" }
    if hasUnseenCompletion { return "checkmark" }
    return nil
  }

  /// Applies the current icon to the status button. The badge is drawn into the
  /// same template image as the glyph (a monochrome corner disc with a symbol
  /// knocked out), so the whole thing keeps the system's menu-bar tinting and
  /// scaling and dims together via `alphaValue` -- no colored overlay needed.
  private func updateStatusIcon() {
    guard let button = statusItem.button else { return }
    let symbol = statusBadgeSymbol
    let dim = statusIconDimAlpha
    guard appliedIcon == nil || appliedIcon! != (symbol, dim) else { return }
    appliedIcon = (symbol, dim)

    let base =
      NSImage(named: "MenuIcon")
      ?? NSImage(systemSymbolName: "brain", accessibilityDescription: nil)

    if let symbol, let base {
      button.image = badgedTemplate(base: base, symbolName: symbol)
    } else {
      base?.isTemplate = true
      button.image = base
    }
    button.alphaValue = dim
  }

  /// Composites the menu bar glyph with a small badge in the top-right corner: a
  /// filled disc with `symbolName` knocked out of it, ringed by a thin
  /// transparent halo so it reads as separate from the glyph. Kept a template
  /// (fill colors are irrelevant -- the menu bar re-tints the whole image).
  private func badgedTemplate(base: NSImage, symbolName: String) -> NSImage {
    let size = base.size
    let image = NSImage(size: size, flipped: false) { rect in
      base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
      guard let ctx = NSGraphicsContext.current else { return true }

      // Badge disc tangent to the top-right corner (stays within the canvas, so
      // it never clips).
      let d = (size.height * 0.6).rounded()
      let disc = NSRect(x: size.width - d, y: size.height - d, width: d, height: d)

      // Punch a 1pt transparent ring around the disc to separate it from the glyph.
      ctx.compositingOperation = .destinationOut
      NSColor.black.setFill()
      NSBezierPath(ovalIn: disc.insetBy(dx: -1, dy: -1)).fill()

      // Solid disc.
      ctx.compositingOperation = .sourceOver
      NSColor.black.setFill()
      NSBezierPath(ovalIn: disc).fill()

      // Knock the symbol out of the disc.
      if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: d * 0.6, weight: .heavy))
      {
        let s = symbol.size
        let symRect = NSRect(
          x: disc.midX - s.width / 2, y: disc.midY - s.height / 2, width: s.width, height: s.height)
        symbol.draw(in: symRect, from: .zero, operation: .destinationOut, fraction: 1)
      }
      return true
    }
    image.isTemplate = true
    return image
  }

  // MARK: - NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    rebuildMenu(menu)
  }

  func menuWillOpen(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    isMenuOpen = true
    // Opening the menu is the user seeing what finished -- clear the checkmark.
    // (A still-active download keeps its arrow: that's derived live from state.)
    if hasUnseenCompletion {
      hasUnseenCompletion = false
      updateStatusIcon()
    }
    modelManager.refreshDownloadedModels()
    // Retry the catalog fetch if it hasn't landed yet (e.g. offline at launch).
    if discoverSuggestions.isEmpty { loadDiscoverSuggestions() }
  }

  func menuDidClose(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    isMenuOpen = false

    // Reset navigation and section collapse state
    selectedModelId = nil
    isInstalledListExpanded = false
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    // Resolve the selected model up front: it decides whether this is the model
    // page or the list, which in turn governs whether the server-status header
    // shows (the page swaps out the header too, not just the body). A selection
    // pointing at a model that's since disappeared (e.g. deleted) falls back to
    // the list. `managedModels` sorts/concats three lists, so snapshot it once —
    // the rest of the rebuild reuses it.
    let managed = modelManager.managedModels
    let pageModel = selectedModelId.flatMap { id in managed.first { $0.id == id } }
    if pageModel == nil { selectedModelId = nil }

    // The server-status header is list chrome, not page chrome: a model page has
    // its own identity header, so skip the global one there.
    if pageModel == nil {
      let view = HeaderView(server: server)
      menu.addItem(NSMenuItem.viewItem(with: view))
      menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))
    }

    // Surface the app-owned CLI install (setting up… / failed + retry) above
    // everything else; without the engine, nothing below it can run.
    let installState = LlamaInstallManager.shared.state
    if installState != .idle {
      menu.addItem(NSMenuItem.viewItem(with: CLISetupView(state: installState)))
      menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))
    }

    // Show warning if custom cache directory is unavailable (e.g., external drive unplugged)
    if UserSettings.hasCustomHFCacheDirectory
      && !FileManager.default.fileExists(atPath: UserSettings.hfCacheDirectory.path)
    {
      addFolderWarning(to: menu)
    }

    // `managed` was snapshotted above (needed there to resolve the page model);
    // the rest of the rebuild reuses it for the installed rows, the Discover
    // filter, the empty-state decision, and the membership snapshot below.
    let suggestions = visibleDiscoverSuggestions(managed: managed)

    // Rows whose tags-hidden title (org prefix + name + params + quant) collides
    // with another installed model's get their id's leftover tags shown as a
    // tiebreaker -- e.g. two "gemma-3 4B Q4_0" installs where one is "it" and
    // one is "it qat". Counted over the full list, not just visible rows, so
    // titles don't change when the list collapses/expands.
    var keyCounts = [String: Int]()
    for model in managed {
      keyCounts[ModelIdParser.displayKey(model.id), default: 0] += 1
    }
    let collidingKeys = Set(keyCounts.filter { $0.value > 1 }.keys)

    // Size the menu to the installed titles before any views are built (every
    // row captures Layout.menuWidth at init). Catalog models fit the base width;
    // org-prefixed ids from power users widen the menu, up to a cap.
    Layout.fitMenuWidth(
      toTitles: managed.map { model in
        Format.modelName(
          id: model.id,
          color: Theme.Colors.textPrimary,
          hasVision: model.hasVisionSupport,
          showTags: collidingKeys.contains(ModelIdParser.displayKey(model.id))
        )
      })

    // A selected model replaces the whole list (header included) with its page,
    // like navigating to a page inside the menu. Resolved above, so a selection
    // whose model has since disappeared already fell back to the list.
    if let pageModel {
      addModelPage(to: menu, model: pageModel, models: managed)
      addFooter(to: menu)
      renderedManagedIds = Set(managed.map(\.id))
      return
    }

    // Always render the Installed section — with rows, or the empty placeholder
    // slot when nothing's installed — so it anchors the menu instead of vanishing
    // and leaving Recommended as a floating first section.
    addInstalledSection(to: menu, models: managed, collidingKeys: collidingKeys)
    addDiscoverSection(to: menu, suggestions: suggestions)

    // The Browse models row lives outside the Recommended section: it's the permanent
    // escape hatch to the full web catalog, so it stays in the same spot whether
    // the picks above are present, exhausted (all installed), or unavailable
    // (offline / still loading).
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))
    menu.addItem(NSMenuItem.viewItem(with: BrowseModelsRow(url: Self.browseCatalogUrl)))

    addFooter(to: menu)

    // Snapshot the membership this build reflects, so the downloads observer can
    // tell a membership change from a progress tick.
    renderedManagedIds = Set(managed.map(\.id))
  }

  // MARK: - Live updates without closing submenus

  private func rebuildMenuIfPossible() {
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }

  /// Registers a main-queue notification observer whose token is cleaned up in deinit.
  private func observe(_ name: Notification.Name, handler: @escaping (Notification) -> Void) {
    let observer = NotificationCenter.default.addObserver(
      forName: name, object: nil, queue: .main
    ) { note in
      MainActor.assumeIsolated {
        handler(note)
      }
    }
    observers.append(observer)
  }

  /// Common case: refresh existing views, optionally rebuilding the menu first.
  private func observe(_ name: Notification.Name, rebuildMenu: Bool = false) {
    observe(name) { [weak self] _ in
      guard let self else { return }
      if rebuildMenu {
        self.rebuildMenuIfPossible()
      }
      self.refresh()
    }
  }

  // Observe server and download changes while the menu is open.
  private func setupObservers() {
    // Server started/stopped - update icon and views. While a model page is
    // open, rebuild instead: its Unload row exists only while that model is
    // loaded, and a plain refresh can't add/remove rows.
    observe(.LBServerStateDidChange) { [weak self] _ in
      guard let self else { return }
      if self.selectedModelId != nil {
        self.rebuildMenuIfPossible()
      }
      self.refresh()
    }

    // CLI install state changed (setting up… / failed) - rebuild to show/hide
    // the setup banner.
    observe(.LBCLIInstallStateDidChange, rebuildMenu: true)

    // Model status changed (loaded/unloaded)
    observe(.LBModelStatusDidChange)

    // Download state changed. A plain progress tick only refreshes existing
    // rows; a membership change (download started/stopped — e.g. from Discover)
    // rebuilds so the row appears or disappears without reopening the menu.
    observe(.LBModelDownloadsDidChange) { [weak self] _ in
      guard let self else { return }
      let currentIds = Set(self.modelManager.managedModels.map(\.id))
      if currentIds != self.renderedManagedIds {
        self.rebuildMenuIfPossible()
      }
      self.refresh()
    }

    // Model downloaded or deleted - rebuild the installed-models section
    observe(.LBModelDownloadedListDidChange, rebuildMenu: true)

    // User settings changed - rebuild menu
    observe(.LBUserSettingsDidChange, rebuildMenu: true)

    // A background flow (e.g. DeeplinkHandler) wants to surface a hint bubble.
    observe(.LBShowMenuHint) { [weak self] note in
      guard let msg = note.userInfo?["message"] as? String else { return }
      self?.showHint(msg)
    }

    // A background flow wants the menu open (e.g. the global-input panel routing
    // to onboarding when no models are installed).
    observe(.LBOpenMenu) { [weak self] _ in
      self?.openMenu()
    }

    // Download failed - show alert
    observe(.LBModelDownloadDidFail) { [weak self] note in
      self?.handleDownloadFailure(notification: note)
    }

    // Download finished - flag it with a checkmark badge (unless the user is
    // already watching the open menu, in which case they've seen it live).
    observe(.LBModelDownloadDidComplete) { [weak self] _ in
      guard let self, !self.isMenuOpen else { return }
      self.hasUnseenCompletion = true
      self.updateStatusIcon()
    }

    refresh()
  }

  deinit {
    // Remove all notification observers to prevent dangling references
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func handleDownloadFailure(notification: Notification) {
    guard let userInfo = notification.userInfo,
      let model = userInfo["model"] as? Model,
      let error = userInfo["error"] as? String
    else { return }

    // Activate the app to ensure the modal alert appears in front of other windows
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = "Download Failed"
    alert.informativeText = "Could not download \(model.displayName).\n\n\(error)"
    alert.addButton(withTitle: "OK")
    ModalPresentation.run { alert.runModal() }
  }

  private func refresh() {
    updateStatusIcon()

    guard let menu = statusItem.menu else { return }
    for item in menu.items {
      if let view = item.view as? HeaderView {
        view.refresh()
      } else if let view = item.view as? ModelItemView {
        view.refresh()
      } else if let view = item.view as? ModelPageHeaderView {
        view.refresh()
      }
    }
  }

  private func addFooter(to menu: NSMenu) {
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))

    let footerView = FooterView(
      llamaVersion: LlamaInstallManager.shared.currentVersion?.tag,
      llamaOrigin: LlamaInstallManager.shared.currentOrigin,
      onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
      onOpenSettings: { [weak self] in self?.openSettings() },
      onQuit: { [weak self] in self?.quitApp() }
    )

    let item = NSMenuItem.viewItem(with: footerView)
    item.isEnabled = true
    menu.addItem(item)
  }

  private func checkForUpdates() {
    NotificationCenter.default.post(name: .LBCheckForUpdates, object: nil)
  }

  private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  // MARK: - Installed Section

  private func addInstalledSection(
    to menu: NSMenu, models: [Model], collidingKeys: Set<String>
  ) {
    // Empty: render the header (no /models link — the server isn't running and
    // there's nothing to list) plus a terse placeholder, so the section still
    // anchors the menu. The decision to render at all lives in rebuildMenu.
    guard !models.isEmpty else {
      menu.addItem(NSMenuItem.viewItem(with: SectionHeaderView(title: "Installed")))
      menu.addItem(NSMenuItem.viewItem(with: EmptyInstalledRow()))
      return
    }

    // "Installed" header with a link to the running server's /models endpoint
    let host = LlamaServer.resolvedHost
    let modelsUrl = URL(string: "http://\(host):\(LlamaServer.port)/models")
    let header = SectionHeaderView(title: "Installed", linkText: "models", linkUrl: modelsUrl)
    menu.addItem(NSMenuItem.viewItem(with: header))

    // Progressive disclosure: a long list pushes the footer (Settings/Quit) past
    // the bottom of the screen, so when collapsed we show only the first
    // `installedCollapsedCount` rows and tuck the rest behind a "Show N more" row.
    // Only worth collapsing when it hides more than a row or two, hence the `+ 2`
    // slack -- otherwise the toggle costs a row without buying any space.
    let isCollapsible = models.count > Self.installedCollapsedCount + 2
    let collapsed = isCollapsible && !isInstalledListExpanded

    var visibleModels = models
    if collapsed {
      // Always keep "live" rows on screen even past the fold -- a running model
      // or an in-flight download below row N would otherwise vanish when
      // collapsed, hiding exactly the rows the user most wants to watch. Only
      // idle models get hidden.
      visibleModels = Array(models.prefix(Self.installedCollapsedCount))
      visibleModels += models.dropFirst(Self.installedCollapsedCount).filter(isLiveRow)
    }

    buildInstalledRows(visibleModels, collidingKeys: collidingKeys)
      .forEach { menu.addItem($0) }

    let hiddenCount = models.count - visibleModels.count
    if collapsed && hiddenCount > 0 {
      addDisclosureRow(to: menu, title: "Show \(hiddenCount) more", expanded: false)
    } else if isCollapsible && isInstalledListExpanded {
      addDisclosureRow(to: menu, title: "Show less", expanded: true)
    }
  }

  /// How many installed rows show before the list collapses behind "Show N more".
  private static let installedCollapsedCount = 8

  /// Adds the collapse/expand toggle and wires it to flip `isInstalledListExpanded`
  /// and rebuild the menu in place (no reopen needed).
  private func addDisclosureRow(to menu: NSMenu, title: String, expanded: Bool) {
    let row = DisclosureRow(title: title, expanded: expanded) { [weak self] in
      guard let self else { return }
      self.isInstalledListExpanded.toggle()
      self.rebuildMenuIfPossible()
    }
    menu.addItem(NSMenuItem.viewItem(with: row))
  }

  /// Whether a row is "live" -- running, loading, or mid-download/paused -- and
  /// so should stay visible even when the list is collapsed.
  private func isLiveRow(_ model: Model) -> Bool {
    if server.isActive(model: model) || server.isLoading(model: model) { return true }
    switch modelManager.status(for: model) {
    case .downloading, .paused: return true
    case .available, .installed: return false
    }
  }

  private func buildInstalledRows(
    _ models: [Model], collidingKeys: Set<String>
  ) -> [NSMenuItem] {
    var items = [NSMenuItem]()

    for model in models {
      let view = ModelItemView(
        model: model,
        server: server,
        modelManager: modelManager,
        actionHandler: actionHandler,
        onOpen: { [weak self] in
          self?.openModelPage(model.id)
        },
        showTags: collidingKeys.contains(ModelIdParser.displayKey(model.id))
      )
      items.append(NSMenuItem.viewItem(with: view))
    }
    return items
  }

  /// Replaces the list body with one model's page. A static header establishes
  /// identity and exposes page-level actions; settings below use the full width.
  private func addModelPage(to menu: NSMenu, model: Model, models: [Model]) {
    let back = TextItemView(text: "Models", style: .back) { [weak self] in
      self?.selectedModelId = nil
      self?.rebuildMenuIfPossible()
    }
    // No separator below the back link: it and the identity header are both
    // page chrome, and a divider would cut navigation apart from the page it
    // belongs to. Whitespace does the grouping.
    menu.addItem(NSMenuItem.viewItem(with: back, minHeight: 28))

    let displayKey = ModelIdParser.displayKey(model.id)
    let showTags = models.filter { ModelIdParser.displayKey($0.id) == displayKey }.count > 1
    let header = ModelPageHeaderView(
      model: model,
      server: server,
      showTags: showTags
    )
    menu.addItem(NSMenuItem.viewItem(with: header))
    menu.addItem(NSMenuItem.viewItem(with: ExpandedModelDetailsView(
      model: model, server: server)))

    // Page actions as labeled menu rows -- bezel buttons read as dialog chrome
    // inside a menu and gray out whenever the app isn't frontmost. Chat leads
    // (the primary action on a model); Unload appears only while the model is
    // loaded (a server-state rebuild keeps it current); Delete closes the set,
    // tinted destructive.
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))
    let chatRow = ActionItemView(title: "Chat with model", symbol: "bubble.left") {}
    chatRow.onAction = { [weak chatRow] in
      // Opened through the row so the menu dismisses with the navigation.
      guard let url = LlamaServer.webuiUrl(modelId: model.id) else { return }
      chatRow?.openInBrowser(url)
    }
    menu.addItem(NSMenuItem.viewItem(with: chatRow))
    let copyRow = ActionItemView(title: "Copy model ID", symbol: "doc.on.doc") {}
    copyRow.onAction = { [weak copyRow] in
      Clipboard.copy(model.id)
      copyRow?.flashConfirmation()
    }
    menu.addItem(NSMenuItem.viewItem(with: copyRow))
    // A one-paste proof the API works end to end (server, port, model id) --
    // the model page is where someone wiring up the API lands first. Sits next
    // to Copy model ID: same workflow (scripting the API), not just same verb.
    let curlRow = ActionItemView(title: "Copy curl command", symbol: "terminal") {}
    curlRow.onAction = { [weak curlRow] in
      Clipboard.copy(LlamaServer.curlCommand(modelId: model.id))
      curlRow?.flashConfirmation()
    }
    menu.addItem(NSMenuItem.viewItem(with: curlRow))
    // The HF model card is where the id pays off -- license, description, the
    // org's other quants. Every managed model is HF-backed, so the id maps
    // straight to a repo URL.
    let hfRow = ActionItemView(title: "View on Hugging Face", symbol: "arrow.up.right") {}
    hfRow.onAction = { [weak hfRow] in
      guard let url = URL(string: "https://huggingface.co/\(model.idBase)") else { return }
      hfRow?.openInBrowser(url)
    }
    menu.addItem(NSMenuItem.viewItem(with: hfRow))
    if server.isActive(model: model) {
      menu.addItem(NSMenuItem.viewItem(with: ActionItemView(
        title: "Unload", symbol: "eject"
      ) { [weak self] in
        self?.actionHandler.performPrimaryAction(for: model)
      }))
    }
    // Disk footprint rides the Delete row -- it's the one place the number
    // informs a decision (how much space deleting reclaims).
    menu.addItem(NSMenuItem.viewItem(with: ActionItemView(
      title: "Delete", symbol: "trash", destructive: true,
      detail: model.totalSize, confirmTitle: "Click again to confirm"
    ) { [weak self] in
      self?.actionHandler.delete(model: model)
    }))
  }

  // MARK: - Discover Section

  /// Featured suggestions minus anything already installed, downloading, or
  /// paused — matched quant-agnostically by running the suggestion's repo
  /// through the same id grammar (`Model.idBase`) the resolver and cache scan
  /// use, so native (ggml-org) models' short ids compare correctly.
  private func visibleDiscoverSuggestions(managed: [Model]) -> [Catalog.Suggestion] {
    let managedIdBases = Set(managed.map(\.idBase))
    return discoverSuggestions.filter {
      !managedIdBases.contains(Model.idBase(orgSlashRepo: $0.repo))
    }
  }

  /// Adds the "Discover" section: a short list of featured models — up to two
  /// device-appropriate picks per family — that install with a single click.
  /// The whole section (divider + header + rows) is omitted when there's nothing
  /// to suggest; the standalone Browse models row below it covers that state.
  private func addDiscoverSection(to menu: NSMenu, suggestions: [Catalog.Suggestion]) {
    guard !suggestions.isEmpty else { return }

    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))

    // Self-describing header: a curated subset recommended for this Mac
    // ("recommended" signals it's not the full compatible set, and the per-Mac
    // framing explains why a family can appear at two sizes).
    let header = SectionHeaderView(title: "Recommended for your Mac")
    menu.addItem(NSMenuItem.viewItem(with: header))

    for suggestion in suggestions {
      let view = CatalogItemView(suggestion: suggestion) { [weak self] suggestion in
        self?.installSuggestion(suggestion)
      }
      menu.addItem(NSMenuItem.viewItem(with: view))
    }
  }

  /// Starts a download for a catalog suggestion via the shared deeplink installer.
  /// The resolve is async (a network round-trip), so we deliberately don't rebuild
  /// here — doing so would flash the empty state while `managedModels` is still
  /// empty. Once the download actually starts, the downloads observer sees the
  /// membership change and rebuilds: the new row appears under Installed and the
  /// suggestion drops out of Discover automatically (its repo is now managed).
  private func installSuggestion(_ suggestion: Catalog.Suggestion) {
    DeeplinkHandler.shared.install(repo: suggestion.repo, quant: suggestion.quant, announce: false)
  }

  private func openModelPage(_ modelId: String) {
    selectedModelId = modelId
    rebuildMenuIfPossible()
  }

  // MARK: - Settings Section

  private func openSettings() {
    // Close the menu first, then open settings window
    statusItem.menu?.cancelTracking()
    NotificationCenter.default.post(name: .LBShowSettings, object: nil)
  }

  // MARK: - Folder Warning

  /// Adds a warning when the custom models folder is unavailable (e.g., external drive unplugged)
  private func addFolderWarning(to menu: NSMenu) {
    let warningView = TextItemView(
      text: "Model directory not available. Check Settings.",
      style: .description,
      onAction: { [weak self] in
        self?.openSettings()
      }
    )
    menu.addItem(NSMenuItem.viewItem(with: warningView))
    menu.addItem(NSMenuItem.viewItem(with: SeparatorView()))
  }
}
