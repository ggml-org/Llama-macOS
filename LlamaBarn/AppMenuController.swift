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
  private var titleView: TitleMenuItemView?

  private var observationTimer: Timer?

  init(modelManager: ModelManager = .shared, server: LlamaServer = .shared) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.modelManager = modelManager
    self.server = server
    // Attempt to read bundled llama.cpp version (fallback to placeholder)
    if let path = Bundle.main.path(forResource: "version", ofType: "txt"),
      let content = try? String(contentsOfFile: path).trimmingCharacters(
        in: .whitespacesAndNewlines),
      !content.isEmpty
    {
      self.llamaCppVersion = content
    } else if let repoPath = Bundle.main.resourcePath?.appending("/llama-cpp/version.txt"),
      let content = try? String(contentsOfFile: repoPath).trimmingCharacters(
        in: .whitespacesAndNewlines),
      !content.isEmpty
    {
      self.llamaCppVersion = content
    } else {
      self.llamaCppVersion = "unknown"
    }
    super.init()
    configureStatusItem()
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
    let tView = TitleMenuItemView(server: server, llamaCppVersion: llamaCppVersion)
    tItem.view = tView
    tView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    titleView = tView
    menu.addItem(tItem)
    menu.addItem(.separator())

    // Installed section header
    let headerItem = NSMenuItem()
    headerItem.title = "Installed"
    headerItem.isEnabled = false
    // Use smaller font (10 pt) for section headers per design update
    headerItem.attributedTitle = NSAttributedString(
      string: headerItem.title,
      attributes: [
        .font: NSFont.systemFont(ofSize: 10),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    )
    menu.addItem(headerItem)

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
        let view = ModelMenuItemView(model: model, server: server, modelManager: modelManager) {
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
      let availHeader = NSMenuItem()
      availHeader.title = "Available"
      availHeader.isEnabled = false
      availHeader.attributedTitle = NSAttributedString(
        string: availHeader.title,
        attributes: [
          .font: NSFont.systemFont(ofSize: 10),
          .foregroundColor: NSColor.secondaryLabelColor,
        ]
      )
      menu.addItem(availHeader)

      for family in sortedFamilies {
        guard let models = familiesDict[family] else { continue }
        let familyItem = NSMenuItem()
        let famView = FamilyMenuItemView(family: family, models: models, modelManager: modelManager)
        familyItem.view = famView
        familyItem.representedObject = family as NSString
        let submenu = NSMenu(title: family)
        submenu.autoenablesItems = false
        let sortedModels = models.sorted { lhs, rhs in
          if lhs.fileSizeMB != rhs.fileSizeMB { return lhs.fileSizeMB < rhs.fileSizeMB }
          return lhs.sizeInBillions < rhs.sizeInBillions
        }
        for model in sortedModels {
          let modelItem = NSMenuItem()
          modelItem.isEnabled = false
          modelItem.representedObject = model.id as NSString
          let view = CatalogModelMenuItemView(model: model, modelManager: modelManager) {
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
    let serverView = ServerStatusMenuItemView(server: server) { [weak self] in
      guard let url = URL(string: "http://localhost:\(LlamaServer.defaultPort)/") else { return }
      NSWorkspace.shared.open(url)
      // Close the menu after opening the UI
      self?.statusItem.menu?.cancelTracking()
    }
    serverItem.view = serverView
    serverView.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
    menu.addItem(serverItem)

    menu.addItem(.separator())
    // Settings-like items previously in ellipsis submenu
    let launchAtLogin = NSMenuItem(
      title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    launchAtLogin.target = self
    launchAtLogin.state = LaunchAtLogin.isEnabled ? .on : .off
    menu.addItem(launchAtLogin)

    let updatesItem = NSMenuItem(
      title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    updatesItem.target = self
    menu.addItem(updatesItem)

    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
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
    // Update dynamic title (memory usage)
    titleView?.refresh()
    statusItem.menu?.items.forEach { menuItem in
      if let view = menuItem.view as? ModelMenuItemView { view.refresh() }
      if let view = menuItem.view as? ServerStatusMenuItemView { view.refresh() }
      // Update all catalog model submenu items
      if let submenu = menuItem.submenu {
        for subItem in submenu.items {
          if let view = subItem.view as? CatalogModelMenuItemView { view.refresh() }
        }
      }
      if let famView = menuItem.view as? FamilyMenuItemView { famView.refresh() }
    }
  }

  // Legacy updateTitleItem removed (replaced by TitleMenuItemView)

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
