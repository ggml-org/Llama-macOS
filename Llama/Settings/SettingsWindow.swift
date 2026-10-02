import SwiftUI

/// Settings window controller -- manages the settings window lifecycle.
/// Uses SwiftUI for the content but AppKit for window management to ensure
/// proper behavior as a menu bar app (no dock icon, proper activation).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowController()

  private var window: NSWindow?

  /// The selected sidebar section. Held here (rather than as SwiftUI state)
  /// because the window title tracks it.
  private let tabSelection = SettingsTabSelection()

  /// Retained so the toolbar delegate can hand out a tracking separator for
  /// this split view.
  private var splitVC: NSSplitViewController?

  /// - Parameter tab: the section to select, or nil to leave the selection
  ///   alone -- reopening the window shouldn't move someone off the pane they
  ///   were last on just because the caller didn't care which one it was.
  func showSettings(tab: SettingsTab? = nil) {
    if let tab { tabSelection.tab = tab }

    // Build the window on first show; afterwards it's reused (and just
    // brought back to the front by the tail of this method).
    if window == nil {
      observeTabChanges()

      // Sidebar pane -- fixed width and non-collapsible: it's the window's
      // only navigation, so there's nothing to gain from hiding it.
      let sidebarHost = NSHostingController(rootView: SettingsSidebar(tabSelection: tabSelection))
      let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
      sidebarItem.canCollapse = false
      sidebarItem.minimumThickness = 170
      sidebarItem.maximumThickness = 170
      sidebarItem.titlebarSeparatorStyle = .none

      let detailHost = NSHostingController(rootView: SettingsView(tabSelection: tabSelection))
      let detailItem = NSSplitViewItem(viewController: detailHost)
      detailItem.titlebarSeparatorStyle = .none

      // An AppKit NSSplitViewController (rather than SwiftUI's
      // NavigationSplitView) is what gives a real full-height sidebar -- one
      // that runs up under the titlebar with the traffic lights sitting on
      // it, as in System Settings.
      let svc = NSSplitViewController()
      svc.addSplitViewItem(sidebarItem)
      svc.addSplitViewItem(detailItem)
      self.splitVC = svc

      let window = NSWindow(contentViewController: svc)
      window.setContentSize(NSSize(width: 700, height: 540))
      window.styleMask = [.titled, .closable, .fullSizeContentView]
      // The title names the selected section and renders in the detail pane's
      // titlebar area, courtesy of the unified toolbar style.
      window.title = tabSelection.tab.title
      window.titleVisibility = .visible
      window.titlebarSeparatorStyle = .none

      // The toolbar itself is empty, but its tracking separator is what tells
      // AppKit where the sidebar divider is -- without it the sidebar stops
      // below the titlebar instead of extending through it.
      let toolbar = NSToolbar(identifier: "SettingsToolbar")
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      window.toolbar = toolbar
      window.toolbarStyle = .unified

      window.isReleasedWhenClosed = false
      window.center()
      window.delegate = self
      self.window = window
    }

    // Show window and activate app
    NSApp.setActivationPolicy(.regular)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Keeps the window title in sync with the selected section. Observation
  /// tracking is one-shot, so the callback re-arms it.
  private func observeTabChanges() {
    withObservationTracking {
      _ = tabSelection.tab
    } onChange: {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        window?.title = tabSelection.tab.title
        observeTabChanges()
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

// MARK: - Toolbar

extension SettingsWindowController: NSToolbarDelegate {
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.sidebarTrackingSeparator]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.sidebarTrackingSeparator]
  }

  func toolbar(
    _ toolbar: NSToolbar,
    itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    guard itemIdentifier == .sidebarTrackingSeparator, let splitVC else { return nil }

    return NSTrackingSeparatorToolbarItem(
      identifier: itemIdentifier,
      splitView: splitVC.splitView,
      dividerIndex: 0
    )
  }
}

/// A single settings row: a title and its description stacked in a left
/// column, with a trailing control (toggle, picker, button) in a right column.
/// The control is vertically centered against the text block, so the gap
/// between title and description stays uniform regardless of the control's
/// height -- unlike a layout where the title shares a row with the control.
struct SettingRow<Control: View>: View {
  let title: String
  let description: String
  @ViewBuilder let control: () -> Control

  var body: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)

        Text(description)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }

      Spacer()

      control()
    }
  }
}

/// A one-line caution shown under a settings row when *another* setting makes
/// this one riskier than it reads on its own.
///
/// Its own element rather than a sentence appended to the description: a
/// description is a stable definition of the setting, so one that mutates
/// leaves the reader unsure whether they misremembered it. Something that
/// appears and disappears is self-evidently conditional.
///
/// Colored the way System Settings colors its own cautions: a yellow glyph
/// carries the alarm, the text stays secondary. All-orange text competes with
/// the setting label above it and reads as an error rather than a caveat.
///
/// The text always names the other setting first, which is what keeps the
/// cause attached to the effect -- a caution that opens with the consequence
/// reads as a fact about the app rather than about a switch you can flip.
struct SettingCaution: View {
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 9))
        .foregroundStyle(.yellow)

      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// A borderless circular-arrow button that resets a setting to its default.
/// Centralizes the reset affordance's glyph, styling, and tooltip so they
/// stay consistent across rows; call sites supply only the reset action and
/// decide when to show it (typically only when a custom value is set).
private struct RestoreDefaultButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.counterclockwise")
        .foregroundStyle(.secondary)
    }
    .buttonStyle(PressableStyle())
    .help("Restore the default")
  }
}

/// The settings window's top-level sections, one per sidebar item.
enum SettingsTab: CaseIterable, Identifiable {
  case general
  case network
  case chat
  case aliases
  case advanced

  var id: Self { self }

  var title: String {
    switch self {
    case .general: "General"
    case .network: "Network"
    case .chat: "Chat"
    case .aliases: "Aliases"
    case .advanced: "Advanced"
    }
  }

  var icon: String {
    switch self {
    case .general: "gearshape"
    case .network: "network"
    case .chat: "bubble"
    case .aliases: "tag"
    case .advanced: "slider.horizontal.3"
    }
  }

  /// Looks a section up by the name the sidebar shows for it.
  ///
  /// Derived from `title` rather than kept as a second list of strings: the
  /// scripting vocabulary is meant to be what's on screen, and a separate
  /// mapping is a thing to forget when a section is renamed. Case-insensitive
  /// because "network" is what someone types.
  init?(sidebarName name: String) {
    guard
      let match = SettingsTab.allCases.first(where: {
        $0.title.caseInsensitiveCompare(name) == .orderedSame
      })
    else { return nil }
    self = match
  }
}

/// The selected section, shared between the sidebar, the detail pane, and the
/// window controller (which mirrors it into the window title).
@Observable
final class SettingsTabSelection {
  var tab: SettingsTab = .general
}

/// The sidebar -- one row per section, with the open-source link pinned below.
struct SettingsSidebar: View {
  @Bindable var tabSelection: SettingsTabSelection

  /// Height of the link's one-row list: a 32pt row (measured off the live view
  /// hierarchy) plus the list's own vertical padding.
  private static let linkListHeight: CGFloat = 40

  /// The gap the list leaves between its last row and its bottom edge -- also
  /// measured, and 2pt shy of the side inset below.
  private static let linkListBottomPadding: CGFloat = 8

  /// How far the list insets a row's selection fill from the pane edge. The
  /// link row draws no fill of its own, but the sections above do -- matching
  /// it below the link keeps the column as far from the bottom edge as from
  /// the sides.
  private static let rowSideInset: CGFloat = 10

  var body: some View {
    VStack(spacing: 0) {
      List(SettingsTab.allCases, selection: $tabSelection.tab) { tab in
        Label(tab.title, systemImage: tab.icon)
      }
      // Set explicitly: hosted in an NSSplitViewItem the list doesn't reliably
      // inherit the sidebar look, and without it renders as a plain table.
      .listStyle(.sidebar)

      // The repository link. It lives in the sidebar rather than at the foot of
      // a tab because its job is to tell people who downloaded the app from the
      // website that it's open source -- that only works if it's on screen
      // whichever section they're looking at.
      //
      // It's a second one-row List rather than a button laid out by hand: the
      // row metrics (height, content inset, the icon-to-title gap) then come
      // from the same list machinery as the sections above, so the link lines up
      // with them by construction. Restating those numbers by hand does not --
      // they aren't API, and they drift with the OS.
      List {
        // Named for the destination, like the rows above -- "Open source" reads
        // as a statement (or worse, as a verb) where every other label in the
        // column is a noun. GitHub goes unsaid: the octocat names it, and the
        // full string wraps at this width.
        // A Button, not a tap gesture: it's what makes the row reachable by
        // keyboard and announced as a control by VoiceOver. `.plain` keeps the
        // label rendering exactly as the list drew it.
        Button {
          NSWorkspace.shared.open(URL(string: "https://github.com/ggml-org/Llama-macOS")!)
        } label: {
          Label {
            Text("Source code")
              .lineLimit(1)
          } icon: {
            Image(.gitHubMark)
              .resizable()
              .frame(width: 14, height: 14)
          }
          // The whole row is the target, not just the text and icon -- height
          // included, so the band above and below the label clicks too.
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          // Trailing arrow: the row leaves the app, unlike every other row in
          // the column, which switches section. It carries that on its own --
          // the row draws no hover fill, so there's no highlight to say it.
          .overlay(alignment: .trailing) {
            Image(systemName: "arrow.up.forward")
              .imageScale(.small)
              // A sidebar list insets its leading edge more than its trailing
              // one (the leading inset is the icon column's allowance), so the
              // arrow would otherwise sit nearer the edge than the octocat
              // does. Measured off the live view, the two sides differ by
              // about this much.
              .padding(.trailing, 8)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .listStyle(.sidebar)
      .scrollDisabled(true)
      // One row's worth of list, so it doesn't claim the empty column above it.
      .frame(height: Self.linkListHeight)
      // The list leaves its own gap under the row; this tops it up to the gap
      // the fill keeps at the sides, so the link isn't nearer the bottom edge
      // than the side edges.
      .padding(.bottom, Self.rowSideInset - Self.linkListBottomPadding)
    }
  }
}

/// Sheet showing the `llama serve` invocation the GUI produces, opened from
/// the Advanced tab.
///
/// Behind a button rather than inline: most people never read it, and inline
/// it filled the tab, which made a tab meant to be skippable look like
/// something to study. Nothing is lost by hiding it -- it reflects settings
/// from the other tabs, so it was never on screen while they changed anyway.
/// A sheet also gets to be wider than the settings pane, so long paths wrap
/// less.
struct ServerCommandSheet: View {
  @Environment(\.dismiss) private var dismiss

  /// Built once per showing: the sheet is modal, so no setting can change
  /// while it's up.
  private let command =
    LlamaServer.buildLaunchSpec()?.displayCommand ?? "llama not installed"

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Titled the way the row that opens it is, with the "you don't run this"
      // right under the title, where the eye lands -- without it, the colored
      // command reads as instructions.
      VStack(alignment: .leading, spacing: 4) {
        Text("Server command")
          .font(.headline)

        Text("See exactly how the app starts the server for you.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // The command itself: monospaced, wrapping, and selectable so a user can
      // read or grab any part of it. Lightly syntax-highlighted to make the
      // structure (env vars, flags, values) easier to scan. Scrolls past a cap
      // so a long set of custom arguments can't push the buttons off screen.
      ScrollView {
        Text(ServerCommandHighlighter.highlight(command))
          .font(.system(size: 11, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
          .padding(10)
      }
      .frame(maxHeight: 360)
      .fixedSize(horizontal: false, vertical: true)
      .background(Color(nsColor: .textBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
      )

      HStack {
        Spacer()

        // The usual reason to open this is to run the command by hand or
        // paste it into a bug report; selecting a dozen wrapped lines is
        // fiddly.
        Button("Copy") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(command, forType: .string)
        }

        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 640)
  }
}

/// The detail pane -- the selected section's form.
struct SettingsView: View {
  var tabSelection: SettingsTabSelection

  private var tab: SettingsTab { tabSelection.tab }

  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var sleepIdleTime = UserSettings.sleepIdleTime
  @State private var agentMode = UserSettings.agentMode
  @State private var hfCacheDir = UserSettings.hfCacheDirectory
  @State private var globalShortcut = UserSettings.globalInputShortcut
  @State private var customWebUIDir = UserSettings.customWebUIDirectory
  @State private var hfToken = UserSettings.hfToken ?? ""
  @State private var showingHFTokenSheet = false
  @State private var showingServerCommandSheet = false
  // Effective server port; re-read after the edit sheet saves so the row updates.
  @State private var serverPort = LlamaServer.port
  @State private var showingServerPortSheet = false
  @State private var networkAccess = UserSettings.networkAccess
  // The code's modules follow the appearance, so the row has to redraw on a
  // theme change.
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.displayScale) private var displayScale

  @ViewBuilder private var form: some View {
    switch tab {
    case .general: generalForm
    case .network: networkForm
    case .chat: chatForm
    case .aliases: AliasesSettingsView()
    case .advanced: advancedForm
    }
  }

  var body: some View {
    form
      // Pull the grouped form up under the transparent titlebar, so its first
      // card sits just below the title rather than a band of empty space.
      .padding(.top, -20)
  }

  /// The General tab -- how the app itself behaves, as distinct from the
  /// server it runs or the models it stores.
  private var generalForm: some View {
    Form {
      // Launch at login section
      Section {
        SettingRow(
          title: "Launch at login",
          description: "Starts with your Mac and waits in the menu bar."
        ) {
          Toggle("", isOn: $launchAtLogin)
            .labelsHidden()
            .onChange(of: launchAtLogin) { _, newValue in
              _ = LaunchAtLogin.setEnabled(newValue)
            }
        }
      }

      // Sleep idle time section
      Section {
        SettingRow(
          title: "Unload when idle",
          description: "Frees memory by unloading the model after this long without use."
        ) {
          PillPicker(
            options: UserSettings.SleepIdleTime.allCases.map { ($0, $0.displayName) },
            selection: Binding(
              get: { sleepIdleTime },
              set: { newValue in
                UserSettings.sleepIdleTime = newValue
                sleepIdleTime = newValue
              }),
            isDebugOnly: { $0.isDebugOnly }
          )
        }
      }

    }
    .formStyle(.grouped)
  }

  /// The Network tab -- how the server is reached: which port, and who's
  /// allowed to connect. Named for the concern rather than for the component,
  /// because that's what decides who can skip the tab: someone who only ever
  /// uses the server from this Mac needs neither setting.
  private var networkForm: some View {
    Form {
      // Server port section
      Section {
        SettingRow(
          title: "Server port",
          description: "The port the server listens on. Default \(String(LlamaServer.defaultPort))."
        ) {
          HStack(spacing: 6) {
            // Only offer a reset when a custom port is set.
            if UserSettings.serverPort != nil {
              RestoreDefaultButton {
                // nil resets to the default; the setter restarts the server once.
                UserSettings.serverPort = nil
                serverPort = LlamaServer.port
              }
            }

            Button {
              showingServerPortSheet = true
            } label: {
              Text(String(serverPort))
            }
            .controlSize(.small)
          }
          .font(.callout)
        }
      }
      .sheet(isPresented: $showingServerPortSheet) {
        ServerPortSheet(currentPort: serverPort) { newPort in
          // nil resets to the default; the setter restarts the server once.
          UserSettings.serverPort = newPort
          serverPort = LlamaServer.port
        }
      }

      // Network access section
      Section {
        networkAccessControl
      }

      // Address section -- only once there's an address another device could
      // actually use.
      if let url = otherDeviceURL {
        Section {
          addressRow(url)
        }
      }

    }
    .formStyle(.grouped)
  }

  /// The URL another device would use to reach the server, or nil when the
  /// server is on loopback -- a QR code for `localhost` would be a code for
  /// the scanning phone's own self, and there's no address worth printing.
  ///
  /// Derived from settings rather than from the running server, so it's right
  /// the instant the option is picked instead of after the restart lands.
  private var otherDeviceURL: URL? {
    let host = LlamaServer.resolvedHost
    guard host != "localhost" else { return nil }
    return URL(string: "http://\(host):\(LlamaServer.port)/")
  }

  /// The address another device would use, with its QR code shown inline.
  ///
  /// Inline rather than behind a button: the code is the whole point of the
  /// row, the pane has the room, and a click to reveal it would only be worth
  /// asking for if it were usually in the way. In the menu it *is* in the way
  /// -- that's a small popup you open dozens of times a day -- which is why
  /// the same code hides behind a button there and sits in the open here.
  private func addressRow(_ url: URL) -> some View {
    HStack(alignment: .top, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Address")

        Text("Open this on another device, or scan the code.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        // The address in text as well as in the code: it's the fallback when
        // a camera won't cooperate, and it's what you'd paste into a config.
        Text(url.absoluteString)
          .font(.system(size: 11, design: .monospaced))
          .textSelection(.enabled)
          .padding(.top, 4)
      }

      Spacer(minLength: 0)

      // No padding around it: the code is transparent and the card is a flat
      // surface, so the card's own margins serve as the quiet zone, at several
      // times the four modules a decoder asks for.
      if let image = QRCode.image(
        for: url.absoluteString, size: QRCode.size, dark: colorScheme == .dark,
        scale: displayScale)
      {
        Image(nsImage: image)
          // No smoothing: blurred module edges are what a camera fails on.
          .interpolation(.none)
      }
    }
  }

  /// The Advanced tab -- settings that are safe to skip: where models are
  /// stored and what authenticates their download, then the server's
  /// internals (the command the app runs, and its log).
  ///
  /// "Advanced" is the macOS convention for exactly that, so the tab answers
  /// "do I need this?" before it's opened. The model settings moved here from
  /// a Downloads tab of their own: almost nobody changes the directory, and
  /// the token is found through the gated-model error that names it, not by
  /// browsing. What it shouldn't become is the home of whatever can't be
  /// placed -- the port and the custom web UI are rarely touched too, but they
  /// clearly belong to Network and Chat.
  ///
  /// Two cards rather than one per row: the rows pair up (models, server),
  /// and the grouping says so without section headers.
  private var advancedForm: some View {
    Form {
      // Models section -- where they're stored, and what authenticates their
      // download.
      Section {
        SettingRow(
          title: "Model directory",
          description: "Where downloaded models are stored."
        ) {
          HStack(spacing: 6) {
            // Only offer a reset when a custom directory is set.
            if UserSettings.hasCustomHFCacheDirectory {
              RestoreDefaultButton {
                UserSettings.hfCacheDirectory = UserSettings.defaultHFCacheDirectory
                hfCacheDir = UserSettings.hfCacheDirectory
                ModelManager.shared.refreshDownloadedModels()
              }
            }

            // One button opens the picker; it shows the current path (already
            // middle-truncated by `abbreviatedPath`) next to a folder icon.
            Button {
              chooseCacheFolder()
            } label: {
              HStack(spacing: 6) {
                Text(abbreviatedPath(hfCacheDir))
                  .lineLimit(1)

                Image(systemName: "folder")
              }
            }
            .controlSize(.small)
          }
          .font(.callout)
        }

        SettingRow(
          title: "Hugging Face token",
          description: "Only needed for gated or private models."
        ) {
          Button {
            showingHFTokenSheet = true
          } label: {
            if hfToken.isEmpty {
              Text("Set")
            } else {
              Text(truncatedToken(hfToken))
            }
          }
          .font(.callout)
          .controlSize(.small)
        }
      }
      .sheet(isPresented: $showingHFTokenSheet) {
        HFTokenSheet(currentToken: hfToken) { newToken in
          hfToken = newToken
          UserSettings.hfToken = newToken.isEmpty ? nil : newToken
        }
      }

      // Server section -- the command the app runs, and the log of what it
      // printed. Side by side because the log is the output of that command.
      Section {
        SettingRow(
          title: "Server command",
          description: "See exactly how the app starts the server for you."
        ) {
          Button("Show") { showingServerCommandSheet = true }
            .font(.callout)
            .controlSize(.small)
        }

        // Opened in Console.app rather than an in-app viewer: Console already
        // follows the file live and has search, so there's nothing to build or
        // maintain.
        SettingRow(
          title: "Server log",
          description: "Output from the current server session."
        ) {
          Button("Open") { openServerLog() }
            .font(.callout)
            .controlSize(.small)
        }
      }
      .sheet(isPresented: $showingServerCommandSheet) {
        ServerCommandSheet()
      }
    }
    .formStyle(.grouped)
  }

  /// The Chat tab -- settings that shape the chat interface the server
  /// serves: what models are allowed to do in it, and how to summon it.
  private var chatForm: some View {
    Form {
      // Agent mode section
      Section {
        // Row and caution share one Form row: as two children of the Section
        // the grouped style would rule a separator between them, which the
        // network tab's caution (nested inside its option) doesn't get.
        VStack(alignment: .leading, spacing: 6) {
        SettingRow(
          title: "Agent mode",
          description: "Lets models read and edit files and run commands on this Mac."
        ) {
          // The setter posts the settings-change notification, which restarts
          // the server with/without `--agent`.
          Toggle(
            "",
            isOn: Binding(
              get: { agentMode },
              set: { newValue in
                UserSettings.agentMode = newValue
                agentMode = newValue
              })
          )
          .labelsHidden()
        }

          if let caution = agentModeCaution {
            SettingCaution(text: caution)
          }
        }
      }

      // Global-input shortcut section. It belongs here rather than in General:
      // the panel it opens only hands the prompt off to the web UI, so the
      // setting is meaningless to someone who uses the server through the API
      // or a third-party app.
      Section {
        SettingRow(
          title: "Quick prompt",
          description: "A keyboard shortcut that opens a prompt window from any app."
        ) {
          HStack(spacing: 6) {
            // Resetting means clearing: no shortcut is the default.
            if globalShortcut != nil {
              RestoreDefaultButton {
                UserSettings.globalInputShortcut = nil
                globalShortcut = nil
              }
            }

            ShortcutRecorder(
              combo: Binding(
                get: { globalShortcut },
                set: { newValue in
                  // The setter posts the change notification that makes the
                  // controller re-register the hotkey immediately.
                  UserSettings.globalInputShortcut = newValue
                  globalShortcut = newValue
                })
            )
          }
          .font(.callout)
        }
      }

      // Custom web UI section. Last in the tab: it's for people building their
      // own chat, a smaller group than either setting above.
      Section {
        // Row, caution and hint share one Form row, like agent mode above, so
        // the grouped style doesn't rule separators between them.
        VStack(alignment: .leading, spacing: 6) {
        SettingRow(
          title: "Custom web UI",
          description: "Serves your own folder in place of the built-in chat."
        ) {
          HStack(spacing: 6) {
            // Resetting means going back to the built-in UI.
            if customWebUIDir != nil {
              RestoreDefaultButton {
                UserSettings.customWebUIDirectory = nil
                customWebUIDir = nil
              }
            }

            // "Choose…" until a folder is set, then the folder itself -- the
            // same button as the model directory, so it reads as a location.
            Button {
              chooseWebUIFolder()
            } label: {
              HStack(spacing: 6) {
                if let customWebUIDir {
                  // Shorter than the model directory's cap: this row shares
                  // its width with the reset button, and the leaf folder (the
                  // part that says which UI it is) must survive truncation.
                  Text(abbreviatedPath(customWebUIDir, maxLen: 28))
                    .lineLimit(1)
                } else {
                  Text("Choose…")
                }

                Image(systemName: "folder")
              }
            }
            .controlSize(.small)
          }
          .font(.callout)
        }

          if let caution = customWebUICaution {
            SettingCaution(text: caution)
          }

          // Only once a folder is set: that's when a browser that has opened
          // the built-in chat can keep showing it. The built-in UI installs a
          // service worker that answers page loads from its cache, and the
          // server can't retire it -- the worker's own update check now gets a
          // 404, which browsers treat as "keep the old one". Clearing the
          // site's data is the fix, and without this line the setting just
          // looks broken.
          if customWebUIDir != nil {
            Text("A browser that has opened the built-in chat may keep showing it until you clear its data for this site.")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  /// The caution for the custom web UI row, or nil when the server is
  /// reachable only from this Mac.
  ///
  /// The server hands out every file in the folder, dotfiles included, so
  /// network access widens who can read it. Shown whether or not a folder is
  /// set, for the same reason as `agentModeCaution`: it's there to inform the
  /// choice, so it has to be readable before it's made.
  private var customWebUICaution: String? {
    guard let who = networkAudience else { return nil }
    return "Network access is on, so \(who) could read every file in the chosen folder."
  }

  /// Opens a folder picker and sets it as the custom web UI.
  ///
  /// Refuses a folder with no `index.html` at its top level: the server would
  /// start fine and then answer the root with a 404, which reads as the app
  /// being broken rather than as the wrong folder. The common way to get there
  /// is picking a project folder instead of its build output, so the alert
  /// says what's missing rather than just "invalid folder".
  private func chooseWebUIFolder() {
    let selection = ModalPresentation.run { () -> URL? in
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.canCreateDirectories = false
      panel.allowsMultipleSelection = false
      panel.message = "Choose a folder with an index.html to serve as the web UI"
      panel.prompt = "Select"
      panel.directoryURL = customWebUIDir

      return panel.runModal() == .OK ? panel.url : nil
    }

    guard let url = selection else { return }

    // Checked before `index.html`, so a project root that also lacks one gets
    // the more specific message.
    if let marker = projectMarker(in: url) {
      ModalPresentation.showAlert(
        style: .warning, title: "This folder has a \(marker)",
        body: "The server hands out every file in the folder, so \(marker) would be readable too. Choose the folder with just the built web UI -- usually build or dist.")
      return
    }

    guard LlamaServer.hasIndexPage(url) else {
      ModalPresentation.showAlert(
        style: .warning, title: "No index.html in this folder",
        body: "Choose the folder that holds your web UI's index.html -- for a project with a build step, that's usually its build output.")
      return
    }

    UserSettings.customWebUIDirectory = url
    customWebUIDir = UserSettings.customWebUIDirectory
  }

  /// The first entry in `dir` that marks it as a project folder rather than a
  /// build output -- `.git`, or an `.env` file -- or nil if there's none.
  ///
  /// The server serves every file in the folder, dotfiles included, so a
  /// project root would hand out its history and secrets. It's also an easy
  /// pick to make by mistake: a plain Vite project keeps its `index.html` at
  /// the root, so the `index.html` check alone would let it through. Only the
  /// top level is checked -- that's where both live in a project root.
  private func projectMarker(in dir: URL) -> String? {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return names.sorted().first { $0 == ".git" || $0 == ".env" || $0.hasPrefix(".env.") }
  }

  /// This Mac's Tailscale address, re-read on every render rather than
  /// captured: signing in, signing out, or switching tailnets while this
  /// window is open all change the answer, and a stale one makes the row
  /// describe a state the server isn't in.
  private var tailscaleAddress: String? {
    TailscaleInterface.address()
  }

  /// The control for network access: every option listed with what it means,
  /// rather than a compact picker whose consequences only appear once you've
  /// already picked. The warning that matters here -- the server has no
  /// password, so "This network" hands it to whoever else is on the wifi --
  /// is only useful *before* the click, which rules out describing the
  /// selected state alone.
  ///
  /// A hand-set address gets a label instead: it was configured outside the
  /// app, so we report it rather than offering to overwrite it.
  @ViewBuilder private var networkAccessControl: some View {
    if case .custom(let address) = networkAccess {
      SettingRow(
        title: "Allow network access", description: "Bound to an address set outside the app."
      ) {
        Text(address)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    } else {
      VStack(alignment: .leading, spacing: 10) {
        Text("Allow network access")

        // The gap between options has to beat the gap inside one, or a
        // description reads as belonging to the option below it as much as to
        // its own -- the pairing is what makes the list scannable.
        VStack(alignment: .leading, spacing: 8) {
          networkAccessOption(.off, title: "Off")
          networkAccessOption(.tailscale, title: "Tailscale")
          networkAccessOption(.localNetwork, title: "This network")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// One radio option: a native-looking radio dot, its title, and the line
  /// saying what choosing it would do. Tailscale is disabled -- shown, but
  /// unpickable -- when this Mac has no Tailscale address, so the control
  /// keeps the same shape whether or not Tailscale is installed. It stays
  /// pickable while *selected* without an address, since deselecting is how
  /// you'd leave that state.
  @ViewBuilder private func networkAccessOption(
    _ option: UserSettings.NetworkAccess, title: String
  ) -> some View {
    let selected = networkAccess == option
    let disabled = option == .tailscale && tailscaleAddress == nil && !selected

    Button {
      setNetworkAccess(option)
    } label: {
      HStack(alignment: .top, spacing: 6) {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
          .foregroundStyle(selected ? Color.accentColor : Color.secondary)
          // Nudge the dot onto the title's optical center
          .padding(.top, 1)

        VStack(alignment: .leading, spacing: 1) {
          // Baseline-aligned, not centered: the address is a smaller font, so
          // centering would float it above the title's baseline.
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)

            // The address this option binds -- a fixed property of the choice,
            // not the URL another device would use (that changes with the
            // network, and the menu shows it for the live state). Monospaced
            // and dim so it reads as an annotation: someone who knows what
            // `0.0.0.0` means gets the whole control at a glance, and someone
            // who doesn't reads the sentence below instead.
            if let bind = networkAccessBindAddress(option) {
              Text(bind)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                // The chip does set the row height at this padding, by a
                // point or so. Deliberate: the address is cramped without it,
                // and the rows stay even because every option has one.
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                // A quiet fill rather than an outline: the port row above
                // renders its value in a bordered control that *is* clickable,
                // and an outlined chip here would borrow that affordance for
                // something inert. A fill reads as a literal, like a code span.
                .background(
                  Color(nsColor: .quaternaryLabelColor).opacity(0.5),
                  in: RoundedRectangle(cornerRadius: 4))
            }
          }

          Text(networkAccessDescription(option))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          // Only on the option that actually exposes the Mac, and only when
          // agent mode makes that exposure mean file access rather than chat.
          if option == .localNetwork, agentMode {
            // "Would", not "gets": this shows on the option whether or not it's
            // selected, so it has to be true of a choice not yet made.
            SettingCaution(text: "Agent mode is on, so anyone who connects would get file access.")
              .padding(.top, 2)
          }

          // Same idea for a custom web UI: every file in its folder is served,
          // so exposing the server exposes the folder.
          if option == .localNetwork, customWebUIDir != nil {
            SettingCaution(text: "A custom web UI is set, so anyone who connects could read every file in its folder.")
              .padding(.top, 2)
          }
        }

        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.5 : 1)
  }

  /// Whether the server is reachable by people other than this Mac's user, so
  /// agent mode's powers are theirs too. Tailscale is deliberately excluded:
  /// it reaches your own devices, which is who the capability was for.
  private var exposedBeyondThisMac: Bool {
    switch networkAccess {
    case .localNetwork, .custom: return true
    case .off, .tailscale: return false
    }
  }

  /// The caution for the agent mode row, or nil when the server is reachable
  /// only from this Mac.
  ///
  /// Deliberately not gated on `agentMode`: the point is to inform the
  /// decision to turn it on, so it has to be readable before the click -- the
  /// same reason the network access options describe themselves rather than
  /// only the chosen one. "Could" rather than "can" is what lets one sentence
  /// serve both states of the toggle.
  ///
  /// Both halves earn their place: naming the setting keeps the cause
  /// attached, and naming the people is what makes it a warning rather than a
  /// status line.
  private var agentModeCaution: String? {
    guard let who = networkAudience else { return nil }
    return "Network access is on, so \(who) could do this too."
  }

  /// Who besides this Mac's user can reach the server, phrased to follow
  /// "so", or nil when it's only them. Shared by the cautions on settings
  /// whose risk grows with network access.
  private var networkAudience: String? {
    guard exposedBeyondThisMac else { return nil }
    if case .custom = networkAccess { return "anything that can reach the server" }
    return "anyone on your current network"
  }

  /// The address `option` binds, or nil when there's nothing true to print
  /// (Tailscale with no address on this Mac).
  private func networkAccessBindAddress(_ option: UserSettings.NetworkAccess) -> String? {
    switch option {
    case .off: return "127.0.0.1"
    case .tailscale: return tailscaleAddress
    case .localNetwork: return "0.0.0.0"
    case .custom(let address): return address
    }
  }

  /// What choosing `option` would do -- written for someone deciding, not for
  /// someone reading back their own setting. Worth varying: the warning that
  /// matters for `.localNetwork` (no password, anyone on this wifi) is simply
  /// untrue of Tailscale, which authenticates every device itself.
  private func networkAccessDescription(_ option: UserSettings.NetworkAccess) -> String {
    switch option {
    case .off:
      return "Only this Mac can reach the server."
    case .tailscale where tailscaleAddress == nil && networkAccess == .tailscale:
      // Selected, but there's no address to bind: the server has fallen back
      // to loopback on its own. Say so rather than describing what the setting
      // would do if Tailscale were running.
      return "Tailscale isn't running, so only this Mac can reach the server for now."
    case .tailscale where tailscaleAddress == nil:
      // Not "Requires Tailscale": detection is by address, so this also
      // covers Tailscale installed but signed out -- and that user would
      // read "requires Tailscale" as wrong rather than as an explanation.
      return "Requires Tailscale to be running."
    case .tailscale:
      return "Reachable from your Tailscale devices, anywhere. Stays invisible on the network you're on."
    case .localNetwork:
      return "Anyone on your current network can reach the server. It has no password -- only turn this on for a network you trust."
    case .custom:
      return "Bound to an address set outside the app."
    }
  }

  /// Writes through to defaults before updating the mirror, so what's derived
  /// from it (the address row, the server command) doesn't render one change
  /// behind. The setter posts the change notification, which restarts the
  /// server on the new host.
  private func setNetworkAccess(_ option: UserSettings.NetworkAccess) {
    UserSettings.setNetworkAccess(option)
    networkAccess = UserSettings.networkAccess
  }


  /// Opens the log in Console.app specifically -- the default app for `.log`
  /// can be a text editor, which shows a snapshot that doesn't update. Falls
  /// back to the default app if Console can't be found.
  private func openServerLog() {
    let log = URL(fileURLWithPath: LlamaServer.logFilePath)
    if let console = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") {
      NSWorkspace.shared.open([log], withApplicationAt: console, configuration: NSWorkspace.OpenConfiguration())
    } else {
      NSWorkspace.shared.open(log)
    }
  }

  /// Opens a folder picker and updates the HF cache directory
  private func chooseCacheFolder() {
    let selection = ModalPresentation.run { () -> URL? in
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.canCreateDirectories = true
      panel.allowsMultipleSelection = false
      panel.message = "Choose a directory for downloaded models"
      panel.prompt = "Select"

      // Start in the current cache directory
      panel.directoryURL = hfCacheDir

      return panel.runModal() == .OK ? panel.url : nil
    }

    if let url = selection {
      UserSettings.hfCacheDirectory = url
      // Re-read for the canonical representation (the panel's URL may
      // differ in trailing slash / symlink resolution)
      hfCacheDir = UserSettings.hfCacheDirectory
      ModelManager.shared.refreshDownloadedModels()
    }
  }

  /// Truncated HF token for display -- e.g. "hf_...xyz1"
  private func truncatedToken(_ token: String) -> String {
    guard token.count > 7 else { return token }
    return "\(token.prefix(3))...\(token.suffix(4))"
  }

  /// Abbreviates a path for display: replaces the home directory with `~`,
  /// then middle-truncates to `maxLen` characters so a long path can't stretch
  /// the layout. Capping the string (rather than the view's width) lets the
  /// label hug short paths instead of always reserving the full cap width.
  private func abbreviatedPath(_ url: URL, maxLen: Int = 38) -> String {
    let path = url.path
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let abbreviated = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path

    guard abbreviated.count > maxLen else { return abbreviated }
    // Keep the head and tail, eliding the middle -- the ends carry the most
    // meaning (the `~`/root and the leaf directory).
    let keep = maxLen - 1  // reserve one char for the ellipsis
    let head = abbreviated.prefix(keep - keep / 2)
    let tail = abbreviated.suffix(keep / 2)
    return "\(head)…\(tail)"
  }
}

/// Compact pill-style segmented picker -- the SwiftUI counterpart of the
/// menu's context tier picker (ExpandedModelDetailsView): a row of clickable
/// pills on a solid neutral background (no outline), echoing the native
/// switch and button styling in the settings window. The selected pill gets
/// a thumb-like solid fill and primary text; hairline dividers separate
/// unselected neighbors.
struct PillPicker<Option: Hashable>: View {
  let options: [(value: Option, label: String)]
  @Binding var selection: Option
  /// Marks options that only exist in DEBUG builds; they're tinted orange so
  /// they're recognizable at a glance without taking extra space
  var isDebugOnly: (Option) -> Bool = { _ in false }

  private var selectedIdx: Int {
    options.firstIndex { $0.value == selection } ?? 0
  }

  var body: some View {
    HStack(spacing: 1) {
      ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
        if idx > 0 {
          divider(hidden: idx == selectedIdx || idx - 1 == selectedIdx)
        }

        let selected = idx == selectedIdx
        // A plain Button (not onTapGesture) -- gestures on Form rows are
        // unreliable on macOS, buttons always receive clicks
        Button {
          selection = option.value
        } label: {
          Text(option.label)
            .font(.callout)
            // All segments use primary text -- dimming the unselected ones
            // reads as disabled; the thumb alone marks the selection (matches
            // native segmented controls)
            // (debug-only options are the exception -- orange flags them)
            .foregroundStyle(
              isDebugOnly(option.value)
                ? Color.orange : Color(nsColor: Theme.Colors.textPrimary))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
              // Thumb-like fill, lighter than the track in both appearances
              selected ? Color(nsColor: Theme.Colors.pillThumb) : .clear,
              in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
      }
    }
    // Equal breathing room between the pills and the row edge on all sides
    .padding(.horizontal, 3)
    .padding(.vertical, 3)
    .background(Color(nsColor: Theme.Colors.pillTrack), in: RoundedRectangle(cornerRadius: 6))
  }

  /// Hairline divider; hidden ones keep their layout slot (clear color) so
  /// pills don't shift as the selection moves. The dividers adjacent to the
  /// selected pill are hidden -- its background already delimits the gap.
  private func divider(hidden: Bool) -> some View {
    Rectangle()
      .fill(hidden ? Color.clear : Color(nsColor: Theme.Colors.separator))
      .frame(width: 1, height: 8)
  }
}

/// Sheet for editing the Hugging Face access token.
struct HFTokenSheet: View {
  let currentToken: String
  let onSave: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var tokenText: String = ""

  private var trimmed: String {
    tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Hugging Face token")
          .font(.headline)

        Text("Only needed for gated or private models.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      TextEditor(text: $tokenText)
        .font(.system(size: 11, design: .monospaced))
        .frame(height: 50)
        .scrollContentBackground(.hidden)
        .padding(.vertical, 4)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )

      HStack {
        // Validation hint replaces the link once there's something to correct.
        if !trimmed.isEmpty && !UserSettings.isValidHFToken(trimmed) {
          Text("Invalid token format")
            .font(.caption)
            .foregroundStyle(.red)
        } else {
          // The sheet is modal, so it needs its own way out to the token page.
          Link(
            "Create a token \u{2197}",
            destination: URL(string: "https://huggingface.co/settings/tokens")!
          )
          .font(.caption)
        }

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("Save") {
          onSave(trimmed)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!trimmed.isEmpty && !UserSettings.isValidHFToken(trimmed))
      }
    }
    .padding(20)
    .frame(width: 400)
    .onAppear {
      tokenText = currentToken
    }
  }
}

/// Sheet for editing the server port. `onSave` receives the new port, or nil
/// to reset to the default (when the field is cleared or set to the default).
struct ServerPortSheet: View {
  let currentPort: Int
  let onSave: (Int?) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var portText: String = ""
  // Set only after a failed Save attempt, so the error isn't flashed while
  // the user is still editing; cleared as soon as the field changes again.
  @State private var error: String?

  private var trimmed: String {
    portText.trimmingCharacters(in: .whitespaces)
  }

  /// Parsed port, or nil if the field isn't a valid in-range number.
  private var parsedPort: Int? {
    guard let port = Int(trimmed), UserSettings.serverPortRange.contains(port) else {
      return nil
    }
    return port
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Server port")
        .font(.headline)

      TextField(String(LlamaServer.defaultPort), text: $portText)
        .textFieldStyle(.roundedBorder)
        // Enter saves, matching the Save button.
        .onSubmit { save() }
        // Editing clears a stale error so it never lingers mid-type.
        .onChange(of: portText) { _, _ in error = nil }

      HStack {
        // Validation hint -- shown only after a failed Save, not while typing.
        if let error {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("Save") {
          save()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 320)
    .onAppear {
      portText = String(currentPort)
    }
  }

  /// Saves the edited port. Empty or the default resets the override (nil).
  /// Otherwise the value must be in range and the port free to bind -- on
  /// failure the sheet stays open with an explanation.
  private func save() {
    if trimmed.isEmpty || parsedPort == LlamaServer.defaultPort {
      onSave(nil)
      dismiss()
      return
    }

    guard let port = parsedPort else {
      let range = UserSettings.serverPortRange
      error = "Port must be between \(String(range.lowerBound)) and \(String(range.upperBound))."
      return
    }

    // Re-selecting the current port is a no-op; skip the availability check,
    // which would otherwise fail because our own server already holds it.
    if port != currentPort && !LlamaServer.isPortAvailable(port) {
      error = "Port \(String(port)) is already in use. Pick another."
      return
    }

    onSave(port)
    dismiss()
  }
}
