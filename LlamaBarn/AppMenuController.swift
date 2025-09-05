import AppKit
import Foundation
import LaunchAtLogin

/// Controls the status bar item and its AppKit menu.
/// First iteration: only an "Installed" section listing downloaded models.
/// Each model row is a custom NSView that lets users start/stop the server
/// without dismissing the menu (like the Wi‑Fi menu behavior).
final class AppMenuController: NSObject, NSMenuDelegate {
  private let statusItem: NSStatusItem
  private let modelManager: ModelManager
  private let server: LlamaServer
  private let llamaCppVersion: String
  private var titleView: HeaderMenuItemView?
  // No stored reference needed for the memory footer.

  private var observationTimer: Timer?

  init(modelManager: ModelManager = .shared, server: LlamaServer = .shared) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager
    self.server = server
    self.llamaCppVersion = AppMenuController.readLlamaCppVersion()
    super.init()
    configureStatusItem()
  }

  private static func readLlamaCppVersion() -> String {
    // Canonical location: bundle resource "version.txt". Fallback to "unknown".
    if let path = Bundle.main.path(forResource: "version", ofType: "txt"),
      let content = try? String(contentsOfFile: path).trimmingCharacters(
        in: .whitespacesAndNewlines),
      !content.isEmpty
    {
      return content
    }
    return "unknown"
  }

  private func configureStatusItem() {
    if let button = statusItem.button {
      // Use existing template images if available; fallback to a simple system symbol
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
    rebuildMenu(menu)
  }

  func menuWillOpen(_ menu: NSMenu) {
    // Ensure we have the latest list of installed models
    modelManager.refreshDownloadedModels()
    startObservation()
  }

  func menuDidClose(_ menu: NSMenu) {
    stopObservation()
  }

  // MARK: - Menu Construction

  private func rebuildMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    // App title + version subtitle at the very top
    let tItem = NSMenuItem()
    tItem.isEnabled = false
    let tView = HeaderMenuItemView(server: server, llamaCppVersion: llamaCppVersion)
    tItem.view = tView
    tView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    titleView = tView
    menu.addItem(tItem)
    menu.addItem(.separator())

    // Installed section header
    menu.addItem(makeSectionHeaderItem("Installed models"))

    // Include downloading models in Installed section (original behavior)
    let downloadingModels = ModelCatalog.models.filter { m in
      if case .downloading = modelManager.getModelStatus(m) { return true }
      return false
    }
    let installed = modelManager.downloadedModels + downloadingModels
    if installed.isEmpty {
      let emptyItem = NSMenuItem()
      emptyItem.title = "No installed models"
      emptyItem.isEnabled = false
      menu.addItem(emptyItem)
    } else {
      for model in installed {
        let item = NSMenuItem()
        item.isEnabled = false  // Keep menu open when interacting with the custom view
        let view = InstalledModelMenuItemView(model: model, server: server, modelManager: modelManager) {
          [weak self] in
          // Rebuild so the row can disappear (if download canceled) or convert to available
          if let menu = self?.statusItem.menu { self?.rebuildMenu(menu) }
        }
        item.view = view
        // Fix height so highlight looks consistent
        item.view?.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        menu.addItem(item)
      }
    }

    // Available (catalog) section
    let familiesDict = Dictionary(grouping: ModelCatalog.models, by: { $0.family })
    let sortedFamilies = familiesDict.keys.sorted()
    if !sortedFamilies.isEmpty {
      menu.addItem(.separator())
      menu.addItem(makeSectionHeaderItem("Catalog"))

      for family in sortedFamilies {
        guard let models = familiesDict[family] else { continue }
        let familyItem = NSMenuItem()
        let famView = FamilyHeaderMenuItemView(family: family, models: models, modelManager: modelManager)
        familyItem.view = famView
        familyItem.representedObject = family as NSString
        let submenu = NSMenu(title: family)
        submenu.autoenablesItems = false
        let sortedModels = models.sorted(by: ModelCatalogEntry.displayOrder(_:_:))
        for model in sortedModels {
          let modelItem = NSMenuItem()
          modelItem.isEnabled = false
          modelItem.representedObject = model.id as NSString
          let view = VariantMenuItemView(model: model, modelManager: modelManager) {
            [weak self] in
            if let menu = self?.statusItem.menu { self?.rebuildMenu(menu) }
          }
          modelItem.view = view
          view.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
          submenu.addItem(modelItem)
        }
        familyItem.submenu = submenu
        menu.addItem(familyItem)
      }
    }

    menu.addItem(.separator())
    // Server status item
    let serverItem = NSMenuItem()
    serverItem.isEnabled = false
    let serverView = ServerMenuItemView(server: server) { [weak self] in
      guard let url = URL(string: "http://localhost:\(LlamaServer.defaultPort)/") else { return }
      NSWorkspace.shared.open(url)
      // Close the menu after opening the UI
      self?.statusItem.menu?.cancelTracking()
    }
    serverItem.view = serverView
    serverView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
    menu.addItem(serverItem)

    menu.addItem(.separator())
    // Settings-like items
    let launchAtLogin = NSMenuItem(
      title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    launchAtLogin.target = self
    launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
    menu.addItem(launchAtLogin)

    let updatesItem = NSMenuItem(
      title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    updatesItem.target = self
    menu.addItem(updatesItem)

    // Footer: show effective system memory (actual or simulated) in Debug builds only
    #if DEBUG
      let memItem = NSMenuItem()
      memItem.isEnabled = false
      let memText = SystemMemory.formatMemory()
      // Use subtle styling like section headers but regular size for readability
      memItem.attributedTitle = NSAttributedString(
        string: memText,
        attributes: [
          .font: NSFont.systemFont(ofSize: 11),
          .foregroundColor: NSColor.secondaryLabelColor,
        ]
      )
      menu.addItem(.separator())
    menu.addItem(memItem)
    #endif

    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
  }

  private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem()
    item.title = title
    item.isEnabled = false
    item.attributedTitle = NSAttributedString(
      string: title,
      attributes: [
        .font: NSFont.systemFont(ofSize: 10),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    )
    return item
  }

  // Periodically refresh status bar icon + row views while menu is open.
  private func startObservation() {
    observationTimer?.invalidate()
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.performRefresh()
    }
    RunLoop.main.add(timer, forMode: .common)
    // Ensure timer also fires while the menu is tracking events
    RunLoop.main.add(timer, forMode: .eventTracking)
    observationTimer = timer
    // Immediate refresh so state change shows instantly
    performRefresh()
  }

  private func stopObservation() {
    observationTimer?.invalidate()
    observationTimer = nil
  }

  private func performRefresh() {
    if let button = statusItem.button {
      let running = server.isRunning
      let imageName = running ? "MenuIconOn" : "MenuIconOff"
      if button.image?.name() != imageName {
        button.image = NSImage(named: imageName) ?? button.image
        button.image?.isTemplate = true
      }
    }
    // Update title
    titleView?.refresh()
    // Update memory footer text to reflect any env var changes or formatting
    // No need to refresh memory footer: RAM doesn't change at runtime, and
    // the menu rebuild sets it correctly on open.
    statusItem.menu?.items.forEach { menuItem in
      if let view = menuItem.view as? InstalledModelMenuItemView { view.refresh() }
      if let view = menuItem.view as? ServerMenuItemView { view.refresh() }
      // Update all catalog model submenu items
      if let submenu = menuItem.submenu {
        for subItem in submenu.items {
          if let view = subItem.view as? VariantMenuItemView { view.refresh() }
        }
      }
      if let famView = menuItem.view as? FamilyHeaderMenuItemView { famView.refresh() }
    }
  }

  // Legacy updateTitleItem removed (replaced by HeaderMenuItemView)

  // MARK: - Catalog Helpers

  // Old catalog item update/action logic removed (replaced with custom view implementation).

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  // MARK: - Settings Item Actions

  @objc private func toggleLaunchAtLogin() {
    // Use LaunchAtLogin package (wraps SMAppService on macOS 13+) to manage login item.
    LaunchAtLogin.isEnabled = !LaunchAtLogin.isEnabled
    if let menu = statusItem.menu { rebuildMenu(menu) }
  }

  @objc private func checkForUpdates() {
    // Ask AppDelegate (which owns Sparkle) to present the updater UI.
    NotificationCenter.default.post(name: .LBCheckForUpdates, object: nil)
  }

}
