import AppKit
import Foundation
import SwiftUI

/// Shared helpers that build individual sections of the status bar menu.
/// Breaks the large MenuController into focused collaborators so each
/// section owns its layout and mutation logic.

private func makeSectionHeaderItem(_ title: String) -> NSMenuItem {
  let view = SectionHeaderView(title: title)
  let item = NSMenuItem.viewItem(with: view)
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
    let header = makeSectionHeaderItem("Installed")
    headerItem = header
    menu.addItem(header)
    populateSection(in: menu)
  }

  /// Rebuilds the installed section.
  /// Called during live updates to keep the UI in sync while menu stays open.
  func rebuild(in menu: NSMenu) {
    guard let range = sectionRange(in: menu) else { return }
    for index in range.reversed() {
      menu.removeItem(at: index)
    }
    populateSection(in: menu)
  }

  func refresh() {
    installedViews.forEach { $0.refresh() }
  }

  private func populateSection(in menu: NSMenu) {
    guard let range = sectionRange(in: menu) else { return }
    let models = installedModels()

    installedViews.removeAll()

    guard !models.isEmpty else {
      menu.insertItem(makePlaceholderItem(), at: range.startIndex)
      return
    }

    models.enumerated().forEach { offset, model in
      let (item, view) = makeInstalledRow(for: model)
      installedViews.append(view)
      menu.insertItem(item, at: range.startIndex + offset)
    }
  }

  private func installedModels() -> [CatalogEntry] {
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
    return item
  }

  private func makeInstalledRow(for model: CatalogEntry) -> (NSMenuItem, InstalledModelItemView) {
    let view = InstalledModelItemView(
      model: model,
      server: server,
      modelManager: modelManager
    ) { [weak self] entry in
      self?.onMembershipChanged(entry)
    }
    let item = NSMenuItem.viewItem(with: view)
    return (item, view)
  }

  private func sectionRange(in menu: NSMenu) -> Range<Int>? {
    guard let headerItem, let headerIndex = menu.items.firstIndex(of: headerItem) else {
      return nil
    }
    // Find the range of items between the section header and the next separator.
    // The section starts immediately after the header (headerIndex + 1).
    // It ends at the first separator found, or at the end of the menu if this is the last section.
    let start = headerIndex + 1
    let end = menu.items[start...].firstIndex(where: \.isSeparatorItem) ?? menu.items.endIndex
    return start..<end
  }
}

@MainActor
final class CatalogSection {
  private let modelManager: ModelManager
  private let onDownloadStatusChange: (CatalogEntry) -> Void
  private var familyViews: [FamilyItemView] = []
  private var catalogViews: [CatalogModelItemView] = []

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

    familyViews.removeAll()
    catalogViews.removeAll()

    for family in families {
      guard let models = modelsByFamily[family.name], !models.isEmpty else { continue }

      let sortedModels = models.sorted(by: CatalogEntry.familyDisplayOrder(_:_:))

      let familyView = FamilyItemView(
        family: family.name,
        sortedModels: sortedModels,
        modelManager: modelManager
      )
      familyViews.append(familyView)

      let familyItem = NSMenuItem.viewItem(with: familyView)
      familyItem.isEnabled = true

      // Build submenu immediately
      let submenu = NSMenu(title: family.name)
      submenu.autoenablesItems = false

      let infoView = FamilyHeaderView(
        familyName: family.name,
        iconName: family.iconName,
        blurb: family.blurb
      )
      submenu.addItem(NSMenuItem.viewItem(with: infoView))
      submenu.addItem(.separator())

      for model in sortedModels {
        let view = CatalogModelItemView(model: model, modelManager: modelManager) {
          [weak self] in
          self?.onDownloadStatusChange(model)
        }
        catalogViews.append(view)
        let modelItem = NSMenuItem.viewItem(with: view)
        submenu.addItem(modelItem)
      }

      familyItem.submenu = submenu
      menu.addItem(familyItem)
    }
  }

  func refresh() {
    familyViews.forEach { $0.refresh() }
    catalogViews.forEach { $0.refresh() }
  }
}

@MainActor
final class FooterSection {
  func add(to menu: NSMenu, menuWidth: CGFloat, isSettingsVisible: Bool) {
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

    let settingsButton = NSButton(title: "Settings", target: nil, action: #selector(toggleSettings))
    settingsButton.font = Typography.secondary
    settingsButton.bezelStyle = .texturedRounded
    settingsButton.translatesAutoresizingMaskIntoConstraints = false
    settingsButton.keyEquivalent = ","

    let quitButton = NSButton(title: "Quit", target: nil, action: #selector(quitApp))
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
    settingsButton.target = self
    settingsButton.action = #selector(toggleSettings)
    quitButton.target = self
    quitButton.action = #selector(quitApp)
    menu.addItem(item)
  }

  @objc private func toggleSettings() {
    NotificationCenter.default.post(name: .LBToggleSettingsVisibility, object: nil)
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }
}
