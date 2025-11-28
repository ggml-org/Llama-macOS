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

  // Catalog Section State
  private var collapsedFamilies: Set<String> = []
  private var knownFamilies: Set<String> = []

  private var isSettingsVisible = false
  private weak var currentlyHighlightedView: ItemView?
  private var welcomePopover: WelcomePopover?

  init(modelManager: ModelManager? = nil, server: LlamaServer? = nil) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager ?? .shared
    self.server = server ?? .shared
    super.init()
    configureStatusItem()
    setupObservers()
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
  }

  func menuDidClose(_ menu: NSMenu) {
    guard menu === statusItem.menu else { return }
    currentlyHighlightedView?.setHighlight(false)
    currentlyHighlightedView = nil
    isSettingsVisible = false
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    // Only manage highlights for enabled items in the root menu (family items, settings, footer).
    // Submenu model items remain disabled and use their own tracking areas for hover.
    // This optimization reduces highlight updates from O(n) to O(1) by tracking only the current view.
    guard menu === statusItem.menu else { return }
    let highlighted = item?.view as? ItemView

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
      rebuildMenu(menu)
    }
    refresh()
  }

  /// Called when family collapse/expand is toggled.
  /// Rebuilds only the catalog section to show/hide models while preserving collapse state.
  private func rebuildCatalogSection() {
    guard let menu = statusItem.menu else { return }
    rebuildMenu(menu)
  }

  /// Helper to observe a notification and call refresh on the main actor
  private func observeAndRefresh(_ name: Notification.Name) {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }
  }

  // Observe server and download changes while the menu is open.
  private func setupObservers() {
    // Server started/stopped - update icon and views
    observeAndRefresh(.LBServerStateDidChange)

    // Server memory usage changed - update running model stats
    observeAndRefresh(.LBServerMemoryDidChange)

    // Download progress updated - refresh progress indicators
    observeAndRefresh(.LBModelDownloadsDidChange)

    // Model downloaded or deleted - rebuild both installed and catalog sections
    NotificationCenter.default.addObserver(
      forName: .LBModelDownloadedListDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        if let menu = self?.statusItem.menu {
          self?.rebuildMenu(menu)
        }
        self?.refresh()
      }
    }

    // User settings changed (e.g., show quantized models) - rebuild menu
    NotificationCenter.default.addObserver(
      forName: .LBUserSettingsDidChange, object: nil, queue: .main
    ) { [weak self] _ in
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

    guard let menu = statusItem.menu else { return }
    for item in menu.items {
      if let view = item.view as? HeaderView {
        view.refresh()
      } else if let view = item.view as? InstalledModelItemView {
        view.refresh()
      } else if let view = item.view as? CatalogModelItemView {
        view.refresh()
      }
    }
  }

  private func addFooter(to menu: NSMenu) {
    menu.addItem(.separator())

    let footerView = FooterView(
      onCheckForUpdates: { [weak self] in self?.checkForUpdates() },
      onOpenSettings: { [weak self] in self?.toggleSettings() },
      onQuit: { [weak self] in self?.quitApp() }
    )

    let hostingView = NSHostingView(rootView: footerView)
    let size = hostingView.fittingSize
    hostingView.frame = NSRect(origin: .zero, size: size)

    let item = NSMenuItem.viewItem(with: hostingView)
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
    menu.addItem(header)

    buildInstalledItems(models).forEach { menu.addItem($0) }
  }

  private func installedModels() -> [CatalogEntry] {
    let downloading = Catalog.allModels().filter { modelManager.isDownloading($0) }
    return (modelManager.downloadedModels + downloading)
      .sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  private func buildInstalledItems(_ models: [CatalogEntry]) -> [NSMenuItem] {
    return models.map { model in
      let view = InstalledModelItemView(
        model: model,
        server: server,
        modelManager: modelManager
      ) { [weak self] entry in
        self?.didChangeDownloadStatus(for: entry)
      }
      return NSMenuItem.viewItem(with: view)
    }
  }

  // MARK: - Catalog Section

  private func addCatalogSection(to menu: NSMenu) {
    var items: [NSMenuItem] = []
    var visibleFamilies: Set<String> = []

    for family in Catalog.families {
      let models = family.allModels.filter { model in
        let isAvailable = !modelManager.isInstalled(model) && !modelManager.isDownloading(model)
        let isCompatible = Catalog.isModelCompatible(model)
        let showQuantized = UserSettings.showQuantizedModels
        return isAvailable && isCompatible && (showQuantized || model.isFullPrecision)
      }

      guard !models.isEmpty else { continue }
      visibleFamilies.insert(family.name)

      // Collect unique sizes for header
      var sizes: [String] = []
      var seenSizes: Set<String> = []
      for model in models {
        if !seenSizes.contains(model.sizeLabel) {
          seenSizes.insert(model.sizeLabel)
          sizes.append(model.sizeLabel)
        }
      }

      let headerView = FamilyHeaderView(
        family: family.name,
        sizes: sizes,
        isCollapsed: collapsedFamilies.contains(family.name)
      ) { [weak self] familyName in
        self?.toggleFamilyCollapsed(familyName)
      }
      let headerItem = NSMenuItem.viewItem(with: headerView)
      // Disable menu management for this item so ItemView handles highlighting via tracking areas.
      // This prevents flicker during menu rebuilds because tracking areas with .initial
      // restore the highlight immediately, whereas NSMenu clears it on rebuild.
      headerItem.isEnabled = false
      items.append(headerItem)

      if !collapsedFamilies.contains(family.name) {
        for model in models {
          let view = CatalogModelItemView(model: model, modelManager: modelManager) {
            [weak self] in
            self?.didChangeDownloadStatus(for: model)
          }
          items.append(NSMenuItem.viewItem(with: view))
        }
      }
    }

    guard !items.isEmpty else { return }

    // Initialize families as collapsed when menu first opens.
    // On subsequent rebuilds during the same session (e.g., toggling settings),
    // preserve the collapse state and collapse any newly appearing families.
    if collapsedFamilies.isEmpty && knownFamilies.isEmpty {
      collapsedFamilies = visibleFamilies
    } else {
      // Add newly appearing families to collapsed state
      let newFamilies = visibleFamilies.subtracting(knownFamilies)
      collapsedFamilies.formUnion(newFamilies)
      collapsedFamilies.formIntersection(visibleFamilies)  // Remove families no longer in catalog
    }
    knownFamilies = visibleFamilies

    let separator = NSMenuItem.separator()
    menu.addItem(separator)

    items.forEach { menu.addItem($0) }
  }

  private func toggleFamilyCollapsed(_ family: String) {
    if collapsedFamilies.contains(family) {
      collapsedFamilies.remove(family)
    } else {
      collapsedFamilies.insert(family)
    }
    rebuildCatalogSection()
  }

  private func getVisibleModels(for family: Catalog.ModelFamily) -> [CatalogEntry] {
    return family.allModels.filter { model in
      let isAvailable = !modelManager.isInstalled(model) && !modelManager.isDownloading(model)
      let isCompatible = Catalog.isModelCompatible(model)
      let showQuantized = UserSettings.showQuantizedModels
      return isAvailable && isCompatible && (showQuantized || model.isFullPrecision)
    }
  }

  private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
    let view = SectionHeaderView(title: title)
    return NSMenuItem.viewItem(with: view)
  }
}
