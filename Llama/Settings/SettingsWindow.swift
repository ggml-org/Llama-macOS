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
    // Size the window to its content *before* centering. macOS 15 (Sequoia)
    // lays out NSHostingView-backed windows more lazily, so without this
    // `center()` runs while the window is still the zero-size placeholder: it
    // centers a 0-height rect and the later content growth expands the window
    // upward from its bottom-left origin -- jamming it against the menu bar.
    // Resolving constraints first gives `center()` the final size to work with.
    window.updateConstraintsIfNeeded()
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
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
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
  // Whether the (informational) server-command section is expanded. Collapsed
  // by default -- it's an advanced, read-only reference, so it shouldn't
  // inflate the window height until a user opens it.
  @State private var serverCommandExpanded = false

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
      // Collapsed by default: it's advanced and informational, so the chevron
      // doubles as a hint that this isn't a primary setting.
      Section {
        // Header row -- the entire row is the toggle target (a generous hit
        // area, unlike a lone chevron), and the label stays flush-left so it
        // lines up with every other row's title. The chevron sits on the
        // trailing edge, rotating to point down when expanded.
        Button {
          serverCommandExpanded.toggle()
        } label: {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Server command")

              Text("The command that starts the server, reflecting your settings above.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary)
              .rotationEffect(.degrees(serverCommandExpanded ? 90 : 0))
          }
          // Extend the tappable region across the full row, gaps included.
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if serverCommandExpanded {
          // The command itself: monospaced, wrapping, and selectable so a user
          // can read or grab any part of it. Lightly syntax-highlighted to make
          // the structure (env vars, flags, values) easier to scan. Its own row
          // in the section (no panel of its own), so the form draws its native
          // separator between the header and the command.
          Text(highlightedCommand)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 680)
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
    _ = (serverPort, sleepIdleTime, hfCacheDir)  // establish SwiftUI dependencies
    return LlamaServer.buildLaunchSpec()?.displayCommand ?? "llama not installed"
  }


  /// Appearance-adaptive palette for the server-command syntax highlighting.
  /// Kept deliberately low-saturation and Xcode-flavored so the block reads as
  /// "structured" rather than a rainbow. Each color carries a light and a dark
  /// variant via `NSColor.dynamic`. Tuned in a standalone playground.
  private enum CommandColors {
    /// `--flags` and the `export` keyword.
    static let flag = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 45 / 255, green: 108 / 255, blue: 168 / 255, alpha: 1),
      dark: NSColor(srgbRed: 111 / 255, green: 176 / 255, blue: 232 / 255, alpha: 1)))
    /// Env-var names (`KEY` in `KEY=value`).
    static let env = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 58 / 255, green: 125 / 255, blue: 92 / 255, alpha: 1),
      dark: NSColor(srgbRed: 143 / 255, green: 208 / 255, blue: 168 / 255, alpha: 1)))
    /// The `serve` subcommand.
    static let serve = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 31 / 255, green: 45 / 255, blue: 92 / 255, alpha: 1),
      dark: NSColor(srgbRed: 155 / 255, green: 180 / 255, blue: 255 / 255, alpha: 1)))
    /// The leading binary path.
    static let path = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 43 / 255, green: 58 / 255, blue: 103 / 255, alpha: 1),
      dark: NSColor(srgbRed: 155 / 255, green: 180 / 255, blue: 255 / 255, alpha: 1)))
    /// Integer values (ports, counts, seconds).
    static let int = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 176 / 255, green: 105 / 255, blue: 31 / 255, alpha: 1),
      dark: NSColor(srgbRed: 217 / 255, green: 165 / 255, blue: 102 / 255, alpha: 1)))
    /// String / path values.
    static let string = Color(nsColor: .dynamic(
      light: NSColor(srgbRed: 160 / 255, green: 74 / 255, blue: 63 / 255, alpha: 1),
      dark: NSColor(srgbRed: 224 / 255, green: 143 / 255, blue: 128 / 255, alpha: 1)))
  }

  /// `serverCommand` with light syntax highlighting applied per token, so the
  /// command's structure is easy to scan. Purely cosmetic -- the underlying
  /// text is identical to `serverCommand`. Coloring rules, by token shape:
  /// `export` and `--flags` share the flag color; env-var names read as keys;
  /// the `serve` subcommand and the leading binary path each get their own
  /// tint; values (env-var RHS and flag arguments) color as integers or
  /// strings; the trailing line-continuation `\` is dimmed.
  private var highlightedCommand: AttributedString {
    var result = AttributedString()

    let lines = serverCommand.components(separatedBy: "\n")
    for (lineIdx, line) in lines.enumerated() {
      if lineIdx > 0 { result.append(AttributedString("\n")) }

      // Preserve the leading indent verbatim, then tokenize the rest.
      let indent = line.prefix { $0 == " " }
      result.append(AttributedString(String(indent)))

      let tokens = tokenize(String(line.dropFirst(indent.count)))
      // `prevWasFlag` marks that the previous token was a `--flag`, so this
      // token is its value and colors as a value rather than by its own shape.
      var prevWasFlag = false
      for (tokenIdx, token) in tokens.enumerated() {
        if tokenIdx > 0 { result.append(AttributedString(" ")) }
        result.append(highlight(token, isFirstOnLine: tokenIdx == 0, isFlagValue: prevWasFlag))
        prevWasFlag = token.hasPrefix("--")
      }
    }

    return result
  }

  /// Splits a command line into space-delimited tokens, but keeps a
  /// single-quoted span (which may contain spaces, e.g. the `models.ini` path)
  /// as a single token so it can be colored as one string.
  private func tokenize(_ line: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var inQuotes = false
    for char in line {
      if char == "'" {
        inQuotes.toggle()
        current.append(char)
      } else if char == " " && !inQuotes {
        tokens.append(current)
        current = ""
      } else {
        current.append(char)
      }
    }
    tokens.append(current)
    return tokens
  }

  /// Colors a single token according to its shape and position (see
  /// `highlightedCommand`).
  private func highlight(_ token: String, isFirstOnLine: Bool, isFlagValue: Bool) -> AttributedString {
    var attr = AttributedString(token)

    if token == "\\" {
      // Trailing line-continuation backslash -- dim, it's just glue.
      attr.foregroundColor = .secondary
    } else if token == "export" {
      // The `export` keyword -- same tint as flags.
      attr.foregroundColor = CommandColors.flag
    } else if token == "serve" {
      // The subcommand.
      attr.foregroundColor = CommandColors.serve
    } else if token.hasPrefix("--") {
      // A flag.
      attr.foregroundColor = CommandColors.flag
    } else if isFlagValue {
      // A flag's argument -- color by its value shape.
      attr.foregroundColor = valueColor(for: token)
    } else if let eq = token.firstIndex(of: "="),
      token[..<eq].allSatisfy({ $0.isUppercase || $0 == "_" }), !token.isEmpty
    {
      // An env-var assignment `KEY=value`: tint the key, color the value by its
      // shape, and leave the `=` default. Built by concatenation so there's no
      // index math or empty-value edge case.
      let value = String(token[token.index(after: eq)...])
      var key = AttributedString(token[..<eq])
      key.foregroundColor = CommandColors.env
      var val = AttributedString(value)
      val.foregroundColor = valueColor(for: value)
      return key + AttributedString("=") + val
    } else if isFirstOnLine && token.contains("/") {
      // The leading binary path on the `llama serve` line.
      attr.foregroundColor = CommandColors.path
    }

    return attr
  }

  /// The color for a value token -- integer tint for all-digit values,
  /// string tint otherwise (paths, quoted strings).
  private func valueColor(for token: String) -> Color {
    let allDigits = !token.isEmpty && token.allSatisfy { $0.isNumber }
    return allDigits ? CommandColors.int : CommandColors.string
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
            // All segments use primary text -- dimming the unselected ones
            // reads as disabled; the thumb alone marks the selection (matches
            // native segmented controls)
            .foregroundStyle(Color(nsColor: Theme.Colors.textPrimary))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
              // Thumb-like fill, lighter than the track in both appearances
              selected ? Color(nsColor: Theme.Colors.pillThumb) : .clear,
              in: RoundedRectangle(cornerRadius: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
