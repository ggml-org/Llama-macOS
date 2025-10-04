import AppKit
import Foundation
import SwiftUI

/// Shared helpers that build individual sections of the status bar menu.
/// Breaks the large MenuController into focused collaborators so each
/// section owns its layout and mutation logic.

/// Typed identifiers for menu items to avoid string-based tag collisions
private enum MenuItemTag {
  case installedHeader
  case installedPlaceholder
  case installedModel(String)  // model id
  case catalogFamily(String)  // family name
  case catalogModel(String)  // model id
}

/// NSObject wrapper for MenuItemTag to store in NSMenuItem.representedObject
private final class MenuItemTagBox: NSObject {
  let tag: MenuItemTag
  init(_ tag: MenuItemTag) {
    self.tag = tag
  }
}

private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
  let view = SectionHeaderView(title: title)
  let item = NSMenuItem.viewItem(with: view, minHeight: 18)
  item.isEnabled = false
  return item
}

@MainActor
final class MenuHeaderSection {
  private let server: LlamaServer
  private var titleView: HeaderView?

  init(server: LlamaServer) {
    self.server = server
  }

  func add(to menu: NSMenu, isSettingsVisible: Bool) {
    let view = HeaderView(
      server: server,
      isSettingsVisible: isSettingsVisible
    )
    titleView = view
    menu.addItem(NSMenuItem.viewItem(with: view, minHeight: 40))
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
    item.isEnabled = true
    menu.addItem(item)
  }
}

@MainActor
final class InstalledSection {
  private enum Constants {
    static let placeholderTitle = "No installed models"
  }

  private let modelManager: ModelManager
  private let server: LlamaServer
  private let onMembershipChanged: (CatalogEntry) -> Void

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
    let header = makeSectionHeaderItem("Installed")
    header.representedObject = MenuItemTagBox(.installedHeader)
    menu.addItem(header)
    populateSection(in: menu)
  }

  /// Rebuilds the installed section if model membership changed (models added/removed).
  /// Called during live updates to keep the UI in sync while menu stays open.
  /// Does nothing if only model state changed (e.g., download progress).
  func rebuildIfNeeded(in menu: NSMenu) {
    guard let range = installedSectionRange(in: menu) else { return }
    let currentModels = getInstalledModels()
    let currentIds = Set(currentModels.map { $0.id })

    // Get existing model IDs in the section
    let existingIds = Set(
      range.compactMap { index -> String? in
        guard let box = menu.items[index].representedObject as? MenuItemTagBox else { return nil }
        if case .installedModel(let id) = box.tag { return id }
        return nil
      })

    // Only rebuild if membership changed (models added/removed)
    if currentIds == existingIds {
      return
    }

    // Membership changed, rebuild the section
    for index in range.reversed() {
      menu.removeItem(at: index)
    }
    populateSection(in: menu)
  }

  private func populateSection(in menu: NSMenu) {
    guard let range = installedSectionRange(in: menu) else { return }
    let installed = getInstalledModels()

    guard !installed.isEmpty else {
      menu.insertItem(makePlaceholderItem(), at: range.startIndex)
      return
    }

    installed.enumerated().forEach { offset, model in
      menu.insertItem(makeInstalledRow(for: model), at: range.startIndex + offset)
    }
  }

  private func getInstalledModels() -> [CatalogEntry] {
    let downloading = Catalog.allEntries().filter {
      if case .downloading = modelManager.status(for: $0) { return true }
      return false
    }
    return (modelManager.downloadedModels + downloading)
      .sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  private func makePlaceholderItem() -> NSMenuItem {
    let item = NSMenuItem()
    item.title = Constants.placeholderTitle
    item.isEnabled = false
    item.representedObject = MenuItemTagBox(.installedPlaceholder)
    return item
  }

  private func makeInstalledRow(for model: CatalogEntry) -> NSMenuItem {
    let view = InstalledModelItemView(
      model: model,
      server: server,
      modelManager: modelManager
    ) { [weak self] entry in
      self?.onMembershipChanged(entry)
    }
    let item = NSMenuItem.viewItem(with: view, minHeight: 28)
    item.representedObject = MenuItemTagBox(.installedModel(model.id))
    return item
  }

  /// Locates the installed section boundaries. The section starts after the header
  /// and ends at the next separator or menu end.
  private func installedSectionRange(in menu: NSMenu) -> Range<Int>? {
    guard
      let headerIndex = menu.items.firstIndex(where: {
        guard let box = $0.representedObject as? MenuItemTagBox else { return false }
        if case .installedHeader = box.tag { return true }
        return false
      })
    else { return nil }

    let start = headerIndex + 1
    let end = menu.items[start...].firstIndex(where: \.isSeparatorItem) ?? menu.items.endIndex
    return start..<end
  }

}

@MainActor
final class CatalogSection: NSObject, NSMenuDelegate {
  private let modelManager: ModelManager
  private let onDownloadStatusChange: (CatalogEntry) -> Void
  private var submenuData: [String: (models: [CatalogEntry], family: Catalog.ModelFamily)] = [:]

  init(
    modelManager: ModelManager,
    onDownloadStatusChange: @escaping (CatalogEntry) -> Void
  ) {
    self.modelManager = modelManager
    self.onDownloadStatusChange = onDownloadStatusChange
  }

  func add(to menu: NSMenu) {
    let showQuantized = UserSettings.showQuantizedModels
    let families = Catalog.families

    guard !families.isEmpty else { return }

    menu.addItem(.separator())
    menu.addItem(makeSectionHeaderItem("Available"))

    // Filter and group all entries once, avoiding N×M work in the family loop
    let allEntries = Catalog.allEntries().filter { showQuantized || $0.isFullPrecision }
    let modelsByFamily = Dictionary(grouping: allEntries, by: \.family)

    submenuData.removeAll()

    for family in families {
      guard let models = modelsByFamily[family.name], !models.isEmpty else { continue }

      let sortedModels = models.sorted(by: CatalogEntry.familyDisplayOrder(_:_:))

      let familyView = FamilyItemView(
        family: family.name,
        sortedModels: sortedModels,
        modelManager: modelManager
      )
      let familyItem = NSMenuItem.viewItem(with: familyView)
      familyItem.isEnabled = true
      familyItem.representedObject = MenuItemTagBox(.catalogFamily(family.name))

      // Create empty submenu with delegate for lazy population
      let submenu = NSMenu(title: family.name)
      submenu.autoenablesItems = false
      submenu.delegate = self
      submenuData[family.name] = (sortedModels, family)

      familyItem.submenu = submenu
      menu.addItem(familyItem)
    }
  }

  // MARK: - NSMenuDelegate (lazy submenu population)

  func menuNeedsUpdate(_ menu: NSMenu) {
    // Only populate if submenu is empty (first open)
    guard menu.items.isEmpty else { return }
    guard let (sortedModels, family) = submenuData[menu.title] else { return }

    let infoView = FamilyInfoView(
      familyName: family.name,
      iconName: family.iconName,
      blurb: family.blurb
    )
    menu.addItem(NSMenuItem.viewItem(with: infoView, minHeight: 56))
    menu.addItem(.separator())

    for model in sortedModels {
      let view = CatalogModelItemView(model: model, modelManager: modelManager) {
        [weak self] in
        self?.onDownloadStatusChange(model)
      }
      let modelItem = NSMenuItem.viewItem(with: view, minHeight: 26)
      modelItem.representedObject = MenuItemTagBox(.catalogModel(model.id))
      menu.addItem(modelItem)
    }
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
      versionText = "build \(AppInfo.buildNumber) • llama.cpp \(AppInfo.llamaCppVersion)"
    } else {
      versionText = "\(AppInfo.shortVersion) • llama.cpp \(AppInfo.llamaCppVersion)"
    }

    let versionLabel = Typography.makePrimaryLabel(versionText)
    versionLabel.lineBreakMode = .byTruncatingMiddle
    versionLabel.translatesAutoresizingMaskIntoConstraints = false

    let quitButton = NSButton(title: "Quit", target: nil, action: #selector(quitApp))
    quitButton.font = Typography.secondary
    quitButton.bezelStyle = .texturedRounded
    quitButton.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(versionLabel)
    container.addSubview(quitButton)

    let horizontalPadding = Metrics.outerHorizontalPadding + Metrics.innerHorizontalPadding

    if menuWidth > 0 {
      container.widthAnchor.constraint(equalToConstant: menuWidth).isActive = true
    }

    NSLayoutConstraint.activate([
      container.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
      versionLabel.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: horizontalPadding),
      versionLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      quitButton.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -horizontalPadding),
      quitButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),

      versionLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: quitButton.leadingAnchor, constant: -8),
    ])

    let item = NSMenuItem.viewItem(with: container, minHeight: 30)
    item.isEnabled = true
    quitButton.target = self
    quitButton.action = #selector(quitApp)
    menu.addItem(item)
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }
}
