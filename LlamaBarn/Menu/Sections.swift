import AppKit
import Foundation
import SwiftUI

/// Shared helpers that build individual sections of the status bar menu.
/// Breaks the large MenuController into focused collaborators so each
/// section owns its layout and mutation logic.

private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
  let view = SectionHeaderView(title: title)
  return NSMenuItem.viewItem(with: view)
}

@MainActor
final class MenuHeaderSection {
  private let server: LlamaServer
  private var titleView: HeaderView?

  init(server: LlamaServer) {
    self.server = server
  }

  func add(to menu: NSMenu) {
    let view = HeaderView(server: server)
    titleView = view
    menu.addItem(NSMenuItem.viewItem(with: view))
    menu.addItem(.separator())
  }

  func refresh() {
    titleView?.refresh()
  }
}

@MainActor
final class MenuSettingsSection {
  func add(to menu: NSMenu, menuWidth: CGFloat) {
    let rootView = SettingsView()
    let view = NSHostingView(rootView: rootView)
    let height = view.fittingSize.height
    view.frame = NSRect(x: 0, y: 0, width: menuWidth, height: height)
    let item = NSMenuItem.viewItem(with: view)
    menu.addItem(item)
  }
}

@MainActor
final class InstalledSection {
  private let modelManager: ModelManager
  private let server: LlamaServer
  private let onMembershipChanged: (CatalogEntry) -> Void

  private var installedViews: [InstalledModelItemView] = []
  private weak var headerItem: NSMenuItem?

  init(
    modelManager: ModelManager,
    server: LlamaServer,
    onMembershipChanged: @escaping (CatalogEntry) -> Void
  ) {
    self.modelManager = modelManager
    self.server = server
    self.onMembershipChanged = onMembershipChanged
  }

  func add(to menu: NSMenu) {
    let models = installedModels()
    guard !models.isEmpty else { return }

    let header = makeSectionHeaderItem("Installed")
    headerItem = header
    menu.addItem(header)

    buildInstalledItems(models).forEach { menu.addItem($0) }
  }

  /// Rebuilds the installed section to reflect current model state.
  /// Called during live updates to keep the UI in sync while menu stays open.
  func rebuild(in menu: NSMenu) {
    let models = installedModels()

    // Case 1: Section exists
    if let headerItem, let headerIndex = menu.items.firstIndex(of: headerItem) {
      // Remove all installed items
      let indexToRemove = headerIndex + 1
      while indexToRemove < menu.items.count {
        let item = menu.items[indexToRemove]
        // Stop when we hit a separator (which marks the end of our section)
        if item.isSeparatorItem { break }
        menu.removeItem(at: indexToRemove)
      }

      if models.isEmpty {
        // No models left - remove the header
        menu.removeItem(at: headerIndex)
        self.headerItem = nil
      } else {
        // Re-add installed items
        let items = buildInstalledItems(models)
        var insertIndex = headerIndex + 1
        for item in items {
          menu.insertItem(item, at: insertIndex)
          insertIndex += 1
        }
      }
      return
    }

    // Case 2: Section doesn't exist - add it if there are models
    guard !models.isEmpty else { return }

    // Find the insertion point after the header separator.
    // The Installed section comes right after the menu header and its separator.
    var insertIndex = 0
    for (index, item) in menu.items.enumerated() {
      if item.isSeparatorItem {
        insertIndex = index + 1
        break
      }
    }

    let header = makeSectionHeaderItem("Installed")
    headerItem = header
    menu.insertItem(header, at: insertIndex)

    let items = buildInstalledItems(models)
    var itemInsertIndex = insertIndex + 1
    for item in items {
      menu.insertItem(item, at: itemInsertIndex)
      itemInsertIndex += 1
    }
  }

  func refresh() {
    installedViews.forEach { $0.refresh() }
  }

  private func installedModels() -> [CatalogEntry] {
    let downloading = Catalog.allEntries().filter { modelManager.isDownloading($0) }
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
        self?.onMembershipChanged(entry)
      }
      installedViews.append(view)
      return NSMenuItem.viewItem(with: view)
    }
  }
}

@MainActor
final class CatalogSection {
  private let modelManager: ModelManager
  private let onDownloadStatusChange: (CatalogEntry) -> Void
  private var catalogViews: [CatalogModelItemView] = []
  private weak var separatorItem: NSMenuItem?
  private var collapsedFamilies: Set<String> = []

  init(
    modelManager: ModelManager,
    onDownloadStatusChange: @escaping (CatalogEntry) -> Void
  ) {
    self.modelManager = modelManager
    self.onDownloadStatusChange = onDownloadStatusChange
  }

  func add(to menu: NSMenu) {
    let availableModels = filterAvailableModels()
    guard !availableModels.isEmpty else { return }

    let separator = NSMenuItem.separator()
    separatorItem = separator
    menu.addItem(separator)

    // Toggle button always at the top
    menu.addItem(makeToggleItem())

    if !UserSettings.catalogCollapsed {
      // Show catalog items when expanded
      buildCatalogItems(availableModels).forEach { menu.addItem($0) }
    }
  }

  /// Rebuilds the catalog section to reflect current model availability.
  /// Called when models move between catalog and installed (e.g., when downloads start/cancel).
  func rebuild(in menu: NSMenu) {
    let availableModels = filterAvailableModels()

    // Case 1: Section exists
    if let separatorItem, let separatorIndex = menu.items.firstIndex(of: separatorItem) {
      // Remove all catalog items (everything after the separator until the next separator or end)
      let indexToRemove = separatorIndex + 1
      while indexToRemove < menu.items.count {
        let item = menu.items[indexToRemove]
        // Stop when we hit a separator (which marks the end of our section)
        if item.isSeparatorItem { break }
        menu.removeItem(at: indexToRemove)
      }

      if availableModels.isEmpty {
        // No models left - remove the separator
        menu.removeItem(at: separatorIndex)
        self.separatorItem = nil
      } else {
        // Re-add toggle button at the top, then catalog items if expanded
        var insertIndex = separatorIndex + 1
        menu.insertItem(makeToggleItem(), at: insertIndex)
        insertIndex += 1

        if !UserSettings.catalogCollapsed {
          let items = buildCatalogItems(availableModels)
          for item in items {
            menu.insertItem(item, at: insertIndex)
            insertIndex += 1
          }
        }
      }
      return
    }

    // Case 2: Section doesn't exist - add it if there are models
    guard !availableModels.isEmpty else { return }

    // Find the footer separator by searching backwards from the end.
    // Insert the catalog section (separator + items) right before it.
    var insertIndex = menu.items.count
    for (index, item) in menu.items.enumerated().reversed() {
      if item.isSeparatorItem {
        insertIndex = index
        break
      }
    }

    let separator = NSMenuItem.separator()
    separatorItem = separator
    menu.insertItem(separator, at: insertIndex)

    var itemInsertIndex = insertIndex + 1
    menu.insertItem(makeToggleItem(), at: itemInsertIndex)
    itemInsertIndex += 1

    if !UserSettings.catalogCollapsed {
      let items = buildCatalogItems(availableModels)
      for item in items {
        menu.insertItem(item, at: itemInsertIndex)
        itemInsertIndex += 1
      }
    }
  }

  /// Filters catalog to show only compatible models that haven't been installed
  private func filterAvailableModels() -> [CatalogEntry] {
    let showQuantized = UserSettings.showQuantizedModels
    return Catalog.allEntries().filter { model in
      let isAvailable = !modelManager.isInstalled(model) && !modelManager.isDownloading(model)
      let isCompatible = Catalog.isModelCompatible(model)
      return isAvailable && isCompatible && (showQuantized || model.isFullPrecision)
    }
  }

  /// Builds a flat list of catalog model items with family headers
  private func buildCatalogItems(_ models: [CatalogEntry]) -> [NSMenuItem] {
    catalogViews.removeAll()

    let sortedModels = models.sorted(by: CatalogEntry.displayOrder(_:_:))
    var items: [NSMenuItem] = []
    var previousFamily: String?

    for model in sortedModels {
      // Insert family header when family changes
      if previousFamily != model.family {
        let headerView = FamilyHeaderView(
          family: model.family,
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
          self?.onDownloadStatusChange(model)
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
    NotificationCenter.default.post(name: .LBUserSettingsDidChange, object: nil)
  }

  func refresh() {
    catalogViews.forEach { $0.refresh() }
  }

  private func makeToggleItem() -> NSMenuItem {
    let toggleView = CatalogToggleView()
    let item = NSMenuItem.viewItem(with: toggleView)
    item.isEnabled = true
    return item
  }
}

@MainActor
final class FooterSection {
  func add(to menu: NSMenu, menuWidth: CGFloat) {
    menu.addItem(.separator())

    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    // Production builds show marketing version without build number;
    // dev/test builds (0.0.0) show only build number
    let versionText: String
    if AppInfo.shortVersion == "0.0.0" {
      versionText = "build \(AppInfo.buildNumber) · llama.cpp \(AppInfo.llamaCppVersion)"
    } else {
      versionText = "\(AppInfo.shortVersion) · llama.cpp \(AppInfo.llamaCppVersion)"
    }

    let versionLabel = Typography.makePrimaryLabel(versionText)
    versionLabel.textColor = .tertiaryLabelColor
    versionLabel.lineBreakMode = .byTruncatingMiddle
    versionLabel.translatesAutoresizingMaskIntoConstraints = false

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

    container.addSubview(versionLabel)
    container.addSubview(settingsButton)
    container.addSubview(quitButton)

    let horizontalPadding = Layout.outerHorizontalPadding + Layout.innerHorizontalPadding

    if menuWidth > 0 {
      container.widthAnchor.constraint(equalToConstant: menuWidth).isActive = true
    }

    NSLayoutConstraint.activate([
      container.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
      versionLabel.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: horizontalPadding),
      versionLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      settingsButton.trailingAnchor.constraint(
        equalTo: quitButton.leadingAnchor, constant: -8),
      settingsButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      quitButton.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -horizontalPadding),
      quitButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      versionLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: settingsButton.leadingAnchor, constant: -8),
    ])

    let item = NSMenuItem.viewItem(with: container)
    item.isEnabled = true
    menu.addItem(item)
  }

  @objc private func toggleSettings() {
    NotificationCenter.default.post(name: .LBToggleSettingsVisibility, object: nil)
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }
}
