import SwiftUI

/// Settings window controller -- manages the settings window lifecycle.
/// Uses SwiftUI for the content but AppKit for window management to ensure
/// proper behavior as a menu bar app (no dock icon, proper activation).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowController()

  private var window: NSWindow?
  private var observer: NSObjectProtocol?

  private override init() {
    super.init()
    // Listen for settings show requests
    observer = NotificationCenter.default.addObserver(
      forName: .LBShowSettings, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.showSettings()
      }
    }
  }

  func showSettings() {
    // If window exists, just bring it to front
    if let window, window.isVisible {
      NSApp.setActivationPolicy(.regular)
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    // Create the SwiftUI content view
    let contentView = SettingsView()

    // Create the window. The contentRect size is just a placeholder: the
    // hosting view resizes the window to fit the SwiftUI content, whose width
    // is pinned by `.frame(width:)` and whose height is intrinsic (`.fixedSize()`).
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Settings"
    window.contentView = NSHostingView(rootView: contentView)
    window.center()
    window.isReleasedWhenClosed = false
    window.delegate = self

    self.window = window

    // Show window and activate app
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

/// A single settings row: a title and its description stacked in a left
/// column, with a trailing control (toggle, picker, button) in a right column.
/// The control is vertically centered against the text block, so the gap
/// between title and description stays uniform regardless of the control's
/// height -- unlike a layout where the title shares a row with the control.
private struct SettingRow<Control: View>: View {
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

/// A borderless circular-arrow button that resets a setting to its default.
/// Centralizes the reset affordance's glyph, styling, and tooltip so they
/// stay consistent across rows; call sites supply only the reset action and
/// decide when to show it (typically only when a custom value is set).
private struct RestoreDefaultButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.counterclockwise")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
    .help("Restore the default")
  }
}

/// SwiftUI view for settings content.
struct SettingsView: View {
  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var sleepIdleTime = UserSettings.sleepIdleTime
  @State private var hfCacheDir = UserSettings.hfCacheDirectory
  @State private var hfToken = UserSettings.hfToken ?? ""
  @State private var showingHFTokenSheet = false
  // Effective server port; re-read after the edit sheet saves so the row updates.
  @State private var serverPort = LlamaServer.port
  @State private var showingServerPortSheet = false
  @State private var customServerArgs = UserSettings.customServerArguments ?? ""
  @State private var showingServerArgsSheet = false

  var body: some View {
    Form {
      // Launch at login section
      Section {
        SettingRow(
          title: "Launch at login",
          description: "Sits idle in the menu bar, using minimal memory."
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
          description: "Auto-unloads model when not in use."
        ) {
          PillPicker(
            options: UserSettings.SleepIdleTime.allCases.map { ($0, $0.displayName) },
            selection: $sleepIdleTime
          )
          .onChange(of: sleepIdleTime) { _, newValue in
            UserSettings.sleepIdleTime = newValue
          }
        }
      }

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

      // Additional server arguments section
      Section {
        SettingRow(
          title: "Additional arguments",
          description: "Extra flags appended to the server command."
        ) {
          HStack(spacing: 6) {
            // Only offer a reset when custom arguments are set.
            if UserSettings.hasCustomServerArguments {
              RestoreDefaultButton {
                UserSettings.customServerArguments = nil
                customServerArgs = UserSettings.customServerArguments ?? ""
              }
            }

            Button {
              showingServerArgsSheet = true
            } label: {
              if customServerArgs.isEmpty {
                Text("Set")
              } else {
                Text(customServerArgs)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
            }
            .controlSize(.small)
          }
          .font(.callout)
        }
      }
      .sheet(isPresented: $showingServerArgsSheet) {
        CustomServerArgumentsSheet(currentValue: customServerArgs) { newValue in
          UserSettings.customServerArguments = newValue.isEmpty ? nil : newValue
          customServerArgs = UserSettings.customServerArguments ?? ""
        }
      }

      // Optional HF access token section
      Section {
        SettingRow(
          title: "Hugging Face Token",
          description: "Authenticate model downloads; optional."
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
      // HF cache directory section
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
      }

      // Server command section -- exposes the actual `llama serve` invocation
      // behind the GUI. It's read-only, but reflects the settings above: change
      // the port, idle timeout, or model directory and the command updates.
      Section {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Server command")

              Text("The command used to start the server.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Copy the full command to the clipboard as a single pasteable line.
            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(serverCommandForCopy, forType: .string)
            } label: {
              Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Copy the command")
          }

          // The command itself: monospaced, wrapping, and selectable so a user
          // can read or grab any part of it. Lightly syntax-highlighted to make
          // the structure (env vars, flags, values) easier to scan.
          Text(highlightedCommand)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 600)
    // Width is pinned above; only the height hugs the content. (A plain
    // `.fixedSize()` would also fix the width to ideal, which forces
    // `maxWidth`-capped controls to their full cap instead of hugging.)
    .fixedSize(horizontal: false, vertical: true)
  }

  /// The shell command that starts the server, built from the current
  /// settings. Reads the `@State` mirrors of the relevant settings (port, idle
  /// timeout, model directory) so SwiftUI recomputes this whenever one of them
  /// changes -- the actual spec is sourced from `LlamaServer` so it stays in
  /// lockstep with what `start()` runs.
  private var serverCommand: String {
    _ = (serverPort, sleepIdleTime, hfCacheDir, customServerArgs)  // establish SwiftUI dependencies
    return LlamaServer.buildLaunchSpec()?.displayCommand ?? "llama not installed"
  }

  /// The single-line form copied to the clipboard -- paste-ready in a terminal.
  private var serverCommandForCopy: String {
    LlamaServer.buildLaunchSpec()?.shellCommand ?? ""
  }

  /// `serverCommand` with light syntax highlighting applied per token, so the
  /// command's structure is easy to scan. Purely cosmetic -- the underlying
  /// text is identical to `serverCommand`. Coloring rules, by token shape:
  /// env-var names (`KEY=`) read as keys, `--flags` as flags, the trailing
  /// line-continuation `\` is dimmed, and everything else stays default.
  private var highlightedCommand: AttributedString {
    var result = AttributedString()

    let lines = serverCommand.components(separatedBy: "\n")
    for (lineIdx, line) in lines.enumerated() {
      if lineIdx > 0 { result.append(AttributedString("\n")) }

      // Split into whitespace-delimited tokens, but keep the leading indent.
      let indent = line.prefix { $0 == " " }
      result.append(AttributedString(String(indent)))

      let tokens = line.dropFirst(indent.count).split(
        separator: " ", omittingEmptySubsequences: false)
      for (tokenIdx, token) in tokens.enumerated() {
        if tokenIdx > 0 { result.append(AttributedString(" ")) }
        result.append(highlight(String(token)))
      }
    }

    return result
  }

  /// Colors a single token according to its shape (see `highlightedCommand`).
  private func highlight(_ token: String) -> AttributedString {
    var attr = AttributedString(token)

    if token == "\\" {
      // Trailing line-continuation backslash -- dim, it's just glue.
      attr.foregroundColor = .secondary
    } else if token.hasPrefix("--") {
      // A flag.
      attr.foregroundColor = .accentColor
    } else if let eq = token.firstIndex(of: "="),
      token[..<eq].allSatisfy({ $0.isUppercase || $0 == "_" }), !token.isEmpty
    {
      // An env-var assignment `KEY=value`: tint just the key.
      var colored = AttributedString(token)
      let keyEnd = colored.index(
        colored.startIndex, offsetByCharacters: token.distance(from: token.startIndex, to: eq))
      colored[colored.startIndex..<keyEnd].foregroundColor = .purple
      return colored
    }

    return attr
  }

  /// Opens a folder picker and updates the HF cache directory
  private func chooseCacheFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose a directory for downloaded models"
    panel.prompt = "Select"

    // Start in the current cache directory
    panel.directoryURL = hfCacheDir

    if panel.runModal() == .OK, let url = panel.url {
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
            .foregroundStyle(
              selected
                ? Color(nsColor: Theme.Colors.textPrimary)
                : Color(nsColor: Theme.Colors.textSecondary)
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
              // Thumb-like solid fill -- the subtle gray used in the menu
              // picker wouldn't read against the row's own background
              selected ? Color(nsColor: .controlBackgroundColor) : .clear,
              in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    // Equal breathing room between the pills and the row edge on all sides
    .padding(.horizontal, 2)
    .padding(.vertical, 2)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
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
        Text("Hugging Face Token")
          .font(.headline)

        HStack(spacing: 4) {
          Text("Don't have one?")
            .foregroundStyle(.secondary)
          Link(
            "Create here \u{2192}",
            destination: URL(string: "https://huggingface.co/settings/tokens")!
          )
        }
        .font(.caption)
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
        // Validation hint
        if !trimmed.isEmpty && !UserSettings.isValidHFToken(trimmed) {
          Text("Invalid token format")
            .font(.caption)
            .foregroundStyle(.red)
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

/// Sheet for editing additional server arguments.
struct CustomServerArgumentsSheet: View {
  let currentValue: String
  let onSave: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var argsText: String = ""

  private var trimmed: String {
    argsText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Additional arguments")
          .font(.headline)

        Text(
          "Passed verbatim to llama serve, after the built-in flags. Example: --threads 8 --temp 0.7"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      TextEditor(text: $argsText)
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
      }
    }
    .padding(20)
    .frame(width: 400)
    .onAppear {
      argsText = currentValue
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
      Text("Server Port")
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

#Preview {
  SettingsView()
}
