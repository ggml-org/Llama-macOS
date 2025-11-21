import AppKit
import Foundation
import SwiftUI

/// Controls the status bar item and its AppKit menu.
/// Breaks menu construction into section helpers so each concern stays focused.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: ModelManager
  private let server: LlamaServer

  // Installed Section State
  private var installedViews: [InstalledModelItemView] = []
  private weak var installedHeaderItem: NSMenuItem?

  // Catalog Section State
  private var catalogViews: [CatalogModelItemView] = []
  private weak var catalogSeparatorItem: NSMenuItem?
  private var collapsedFamilies: Set<String> = []
  private var knownFamilies: Set<String> = []

  private var headerView: HeaderView?
  private var isSettingsVisible = false
  private let observer = NotificationObserver()
  private weak var currentlyHighlightedView: ItemView?
  private var preservingHighlightForFamily: String?
  private var welcomePopover: WelcomePopover?

  init(modelManager: ModelManager? = nil, server: LlamaServer? = nil) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager ?? .shared
    self.server = server ?? .shared
    super.init()
    configureStatusItem()
    showWelcomeIfNeeded()
  }

  private func showWelcomeIfNeeded() {
    guard !UserSettings.hasSeenWelcome else { return }

    // Show after a short delay to ensure the status item is visible
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      guard let self else { return }
      let popover = WelcomePopover()
      popover.show(from: self.statusItem)
      self.welcomePopover = popover
      UserSettings.hasSeenWelcome = true
    }
  }

  private func configureStatusItem() {
    if let button = statusItem.button {
      button.image =
        NSImage(named: server.isRunning ? "MenuIconOn" : "MenuIconOff")
        ?? NSImage(systemSymbolName: "brain", accessibilityDescription: nil)
      button.image?.isTemplate = true
    }

    let menu = NSMenu()
    menu.delegate = self
    menu.autoenablesItems = false
    statusItem.menu = menu
  }

  // MARK: - NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    rebuildMenu(menu)
  }

  func menuWillOpen(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    modelManager.refreshDownloadedModels()
    addObservers()
  }

  func menuDidClose(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    currentlyHighlightedView?.setHighlight(false)
    currentlyHighlightedView = nil
    preservingHighlightForFamily = nil
    observer.removeAll()
    isSettingsVisible = false

    collapsedFamilies.removeAll()
    knownFamilies.removeAll()
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    // Only manage highlights for enabled items in the root menu (family items, settings, footer).
    // Submenu model items remain disabled and use their own tracking areas for hover.
    // This optimization reduces highlight updates from O(n) to O(1) by tracking only the current view.
    guard menu === statusItem.menu else { return }
    let highlighted = item?.view as? ItemView

    // During catalog rebuilds, preserve the highlight on the family header being toggled
    // to avoid flicker when the old view is destroyed and the new one is created
    if preservingHighlightForFamily != nil && highlighted == nil {
      return
    }

    if currentlyHighlightedView !== highlighted {
      currentlyHighlightedView?.setHighlight(false)
      highlighted?.setHighlight(true)
      currentlyHighlightedView = highlighted
    }
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let view = HeaderView(server: server)
    headerView = view
    menu.addItem(NSMenuItem.viewItem(with: view))
    menu.addItem(.separator())

    addInstalledSection(to: menu)
    addCatalogSection(to: menu)
    addFooter(to: menu)

    if isSettingsVisible {
      menu.addItem(.separator())
      let rootView = SettingsView()
      let view = NSHostingView(rootView: rootView)
      let height = view.fittingSize.height
      view.frame = NSRect(x: 0, y: 0, width: Layout.menuWidth, height: height)
      let item = NSMenuItem.viewItem(with: view)
      menu.addItem(item)
    }
  }

  // MARK: - Live updates without closing submenus

  /// Called from model rows when a user starts/cancels a download.
  /// Rebuilds both installed and catalog sections to reflect changes while keeping submenus open.
  private func didChangeDownloadStatus(for _: CatalogEntry) {
    if let menu = statusItem.menu {
      rebuildInstalledSection(in: menu)
      updateCatalogItems(in: menu)
    }
    refresh()
  }

  /// Called when family collapse/expand is toggled.
  /// Rebuilds only the catalog section to show/hide models while preserving collapse state.
  private func rebuildCatalogSection() {
    guard let menu = statusItem.menu else { return }

    // Remember which family header was highlighted before rebuilding
    let highlightedFamily = (currentlyHighlightedView as? FamilyHeaderView)?.family

    // Set flag to prevent unhighlighting during rebuild
    preservingHighlightForFamily = highlightedFamily

    updateCatalogItems(in: menu)

    // Re-highlight the family header if it was highlighted before rebuilding.
    // Use a short delay to let the menu system settle after the rebuild.
    guard let family = highlightedFamily else {
      preservingHighlightForFamily = nil
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self, let currentMenu = self.statusItem.menu, currentMenu === menu else {
        self?.preservingHighlightForFamily = nil
        return
      }
      defer { self.preservingHighlightForFamily = nil }

      if let headerView = self.findFamilyHeader(for: family, in: currentMenu) {
        headerView.setHighlight(true)
        self.currentlyHighlightedView = headerView
      }
    }
  }

  /// Finds the FamilyHeaderView for a given family name in the menu.
  private func findFamilyHeader(for family: String, in menu: NSMenu) -> FamilyHeaderView? {
    menu.items.lazy.compactMap { $0.view as? FamilyHeaderView }
      .first { $0.family == family }
  }

  /// Helper to observe a notification and call refresh on the main actor
  private func observeAndRefresh(_ name: Notification.Name) {
    observer.observe(name) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }
  }

  // Observe server and download changes while the menu is open.
  private func addObservers() {
    observer.removeAll()

    // Server started/stopped - update icon and views
    observeAndRefresh(.LBServerStateDidChange)

    // Server memory usage changed - update running model stats
    observeAndRefresh(.LBServerMemoryDidChange)

    // Download progress updated - refresh progress indicators
    observeAndRefresh(.LBModelDownloadsDidChange)

    // Model downloaded or deleted - rebuild both installed and catalog sections
    observer.observe(.LBModelDownloadedListDidChange) { [weak self] _ in
      MainActor.assumeIsolated {
        if let menu = self?.statusItem.menu {
          self?.rebuildInstalledSection(in: menu)
          self?.updateCatalogItems(in: menu)
        }
        self?.refresh()
      }
    }

    // User settings changed (e.g., show quantized models) - rebuild menu
    observer.observe(.LBUserSettingsDidChange) { [weak self] _ in
      MainActor.assumeIsolated {
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
      }
    }

    refresh()
  }

  private func refresh() {
    if let button = statusItem.button {
      let running = server.isRunning
      let imageName = running ? "MenuIconOn" : "MenuIconOff"
      if button.image?.name() != imageName {
        button.image = NSImage(named: imageName) ?? button.image
        button.image?.isTemplate = true
      }
    }

    headerView?.refresh()
    installedViews.forEach { $0.refresh() }
    catalogViews.forEach { $0.refresh() }
  }

  private func addFooter(to menu: NSMenu) {
    menu.addItem(.separator())

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let appVersionText: String
    #if DEBUG
      // Debug builds show hammer emoji
      appVersionText = "🔨"
    #else
      appVersionText =
        AppInfo.shortVersion == "0.0.0"
        // Internal builds (0.0.0) show build number
        ? "build \(AppInfo.buildNumber)"
        // Public builds show marketing version
        : AppInfo.shortVersion
    #endif

    let versionButton = NSButton(title: "", target: self, action: #selector(checkForUpdates))
    versionButton.isBordered = false
    versionButton.translatesAutoresizingMaskIntoConstraints = false
    versionButton.lineBreakMode = .byTruncatingMiddle
    versionButton.attributedTitle = NSAttributedString(
      string: appVersionText,
      attributes: [
        .font: Typography.primary,
        .foregroundColor: NSColor.tertiaryLabelColor,
      ])
    (versionButton.cell as? NSButtonCell)?.highlightsBy = []

    let llamaCppLabel = Typography.makePrimaryLabel(" · llama.cpp \(AppInfo.llamaCppVersion)")
    llamaCppLabel.textColor = .tertiaryLabelColor
    llamaCppLabel.lineBreakMode = .byTruncatingMiddle
    llamaCppLabel.translatesAutoresizingMaskIntoConstraints = false

    let settingsButton = NSButton(
      title: "Settings", target: self, action: #selector(toggleSettings))
    settingsButton.font = Typography.secondary
    settingsButton.bezelStyle = .texturedRounded
    settingsButton.translatesAutoresizingMaskIntoConstraints = false
    settingsButton.keyEquivalent = ","

    let quitButton = NSButton(title: "Quit", target: self, action: #selector(quitApp))
    quitButton.font = Typography.secondary
    quitButton.bezelStyle = .texturedRounded
    quitButton.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(versionButton)
    container.addSubview(llamaCppLabel)
    container.addSubview(settingsButton)
    container.addSubview(quitButton)

    let horizontalPadding = Layout.outerHorizontalPadding + Layout.innerHorizontalPadding

    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: Layout.menuWidth),
      container.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
      versionButton.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: horizontalPadding),
      versionButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      llamaCppLabel.leadingAnchor.constraint(equalTo: versionButton.trailingAnchor),
      llamaCppLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      settingsButton.trailingAnchor.constraint(
        equalTo: quitButton.leadingAnchor, constant: -8),
      settingsButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      quitButton.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -horizontalPadding),
      quitButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      llamaCppLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -8),
    ])

    let item = NSMenuItem.viewItem(with: container)
    item.isEnabled = true
    menu.addItem(item)
  }

  @objc private func checkForUpdates() {
    NotificationCenter.default.post(name: .LBCheckForUpdates, object: nil)
  }

  @objc private func toggleSettings() {
    isSettingsVisible.toggle()
    if let menu = statusItem.menu {
      rebuildMenu(menu)
    }
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  // MARK: - Installed Section

  private func addInstalledSection(to menu: NSMenu) {
    let models = installedModels()
    guard !models.isEmpty else { return }

    let header = makeSectionHeaderItem("Installed")
    installedHeaderItem = header
    menu.addItem(header)

    buildInstalledItems(models).forEach { menu.addItem($0) }
  }

  private func rebuildInstalledSection(in menu: NSMenu) {
    let models = installedModels()

    // Case 1: Section exists
    if let installedHeaderItem, let headerIndex = menu.items.firstIndex(of: installedHeaderItem) {
      menu.replaceItems(after: installedHeaderItem, with: buildInstalledItems(models))

      if models.isEmpty {
        // No models left - remove the header
        menu.removeItem(at: headerIndex)
        self.installedHeaderItem = nil
      }
      return
    }

    // Case 2: Section doesn't exist - add it if there are models
    guard !models.isEmpty else { return }

    // Find the insertion point after the header separator.
    // The Installed section comes right after the menu header and its separator.
    guard let insertIndex = menu.indexOfFirstSeparator.map({ $0 + 1 }) else { return }

    let header = makeSectionHeaderItem("Installed")
    installedHeaderItem = header
    menu.insertItem(header, at: insertIndex)

    let items = buildInstalledItems(models)
    menu.insertItems(items, at: insertIndex + 1)
  }

  private func installedModels() -> [CatalogEntry] {
    let downloading = Catalog.allModels().filter { modelManager.isDownloading($0) }
    return (modelManager.downloadedModels + downloading)
      .sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  private func buildInstalledItems(_ models: [CatalogEntry]) -> [NSMenuItem] {
    installedViews.removeAll()

    return models.map { model in
      let view = InstalledModelItemView(
        model: model,
        server: server,
        modelManager: modelManager
      ) { [weak self] entry in
        self?.didChangeDownloadStatus(for: entry)
      }
      installedViews.append(view)
      return NSMenuItem.viewItem(with: view)
    }
  }

  // MARK: - Catalog Section

  private func addCatalogSection(to menu: NSMenu) {
    let availableModels = filterAvailableModels()
    guard !availableModels.isEmpty else { return }

    // Initialize families as collapsed when menu first opens.
    // On subsequent rebuilds during the same session (e.g., toggling settings),
    // preserve the collapse state and collapse any newly appearing families.
    let families = Set(availableModels.map { $0.family })
    if collapsedFamilies.isEmpty && knownFamilies.isEmpty {
      collapsedFamilies = families
    } else {
      // Add newly appearing families to collapsed state
      let newFamilies = families.subtracting(knownFamilies)
      collapsedFamilies.formUnion(newFamilies)
      collapsedFamilies.formIntersection(families)  // Remove families no longer in catalog
    }
    knownFamilies = families

    let separator = NSMenuItem.separator()
    catalogSeparatorItem = separator
    menu.addItem(separator)

    buildCatalogItems(availableModels).forEach { menu.addItem($0) }
  }

  private func updateCatalogItems(in menu: NSMenu) {
    let availableModels = filterAvailableModels()

    // Case 1: Section exists
    if let catalogSeparatorItem,
      let separatorIndex = menu.items.firstIndex(of: catalogSeparatorItem)
    {
      menu.replaceItems(after: catalogSeparatorItem, with: buildCatalogItems(availableModels))

      if availableModels.isEmpty {
        // No models left - remove the separator
        menu.removeItem(at: separatorIndex)
        self.catalogSeparatorItem = nil
      }
      return
    }

    // Case 2: Section doesn't exist - add it if there are models
    guard !availableModels.isEmpty else { return }

    // Find the footer separator by searching backwards from the end.
    // Insert the catalog section (separator + items) right before it.
    guard let insertIndex = menu.indexOfLastSeparator else { return }

    let separator = NSMenuItem.separator()
    catalogSeparatorItem = separator
    menu.insertItem(separator, at: insertIndex)

    let items = buildCatalogItems(availableModels)
    menu.insertItems(items, at: insertIndex + 1)
  }

  private func filterAvailableModels() -> [CatalogEntry] {
    let showQuantized = UserSettings.showQuantizedModels
    return Catalog.allModels().filter { model in
      let isAvailable = !modelManager.isInstalled(model) && !modelManager.isDownloading(model)
      let isCompatible = Catalog.isModelCompatible(model)
      return isAvailable && isCompatible && (showQuantized || model.isFullPrecision)
    }
  }

  private func buildCatalogItems(_ models: [CatalogEntry]) -> [NSMenuItem] {
    catalogViews.removeAll()

    let sortedModels = models.sorted(by: CatalogEntry.displayOrder(_:_:))

    // Group models by family to collect unique sizes
    var familySizes: [String: [String]] = [:]
    for model in sortedModels {
      if !familySizes[model.family, default: []].contains(model.sizeLabel) {
        familySizes[model.family, default: []].append(model.sizeLabel)
      }
    }

    var items: [NSMenuItem] = []
    var previousFamily: String?

    for model in sortedModels {
      // Insert family header when family changes
      if previousFamily != model.family {
        let sizes = familySizes[model.family] ?? []
        let headerView = FamilyHeaderView(
          family: model.family,
          sizes: sizes,
          isCollapsed: collapsedFamilies.contains(model.family)
        ) { [weak self] family in
          self?.toggleFamilyCollapsed(family)
        }
        let headerItem = NSMenuItem.viewItem(with: headerView)
        headerItem.isEnabled = true
        items.append(headerItem)
      }

      // Only add model if family is not collapsed
      if !collapsedFamilies.contains(model.family) {
        let view = CatalogModelItemView(model: model, modelManager: modelManager) {
          [weak self] in
          self?.didChangeDownloadStatus(for: model)
        }
        catalogViews.append(view)
        items.append(NSMenuItem.viewItem(with: view))
      }

      previousFamily = model.family
    }

    return items
  }

  private func toggleFamilyCollapsed(_ family: String) {
    if collapsedFamilies.contains(family) {
      collapsedFamilies.remove(family)
    } else {
      collapsedFamilies.insert(family)
    }
    rebuildCatalogSection()
  }

  private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
    let view = SectionHeaderView(title: title)
    return NSMenuItem.viewItem(with: view)
  }
}
