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

    // Create the window
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
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

/// SwiftUI view for settings content.
struct SettingsView: View {
  @State private var launchAtLogin = LaunchAtLogin.isEnabled
  @State private var sleepIdleTime = UserSettings.sleepIdleTime
  @State private var hfCacheDir = UserSettings.hfCacheDirectory
  @State private var hfToken = UserSettings.hfToken ?? ""
  @State private var showingHFTokenSheet = false

  var body: some View {
    Form {
      // Launch at login section
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
              _ = LaunchAtLogin.setEnabled(newValue)
            }

          Text("Sits idle in the menu bar, using minimal memory.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }

      // Sleep idle time section
      Section {
        VStack(alignment: .leading, spacing: 4) {
          LabeledContent("Unload when idle") {
            PillPicker(
              options: UserSettings.SleepIdleTime.allCases.map { ($0, $0.displayName) },
              selection: $sleepIdleTime
            )
            .onChange(of: sleepIdleTime) { _, newValue in
              UserSettings.sleepIdleTime = newValue
            }
          }

          Text("Auto-unloads model when not in use.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }

      // Optional HF access token section
      Section {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Hugging Face Token")
            Spacer()
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

          Text("Authenticate model downloads; optional.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 4) {
          Text("Cache directory")

          Text("Where downloaded models are stored.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

          HStack(spacing: 6) {
            // Current path in a "well" -- a quiet fill, not a bordered
            // field, so it reads as a displayed value, not an editable input
            // (extra top padding separates the control row from the caption)
            HStack(spacing: 6) {
              Text(abbreviatedPath(hfCacheDir))
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

              Spacer(minLength: 0)

              Button {
                NSWorkspace.shared.activateFileViewerSelecting([hfCacheDir])
              } label: {
                Image(systemName: "folder")
              }
              .buttonStyle(.plain)
              .foregroundStyle(.secondary)
              .help("Show in Finder")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            // Show a reset button only when a custom directory is set
            if UserSettings.hasCustomHFCacheDirectory {
              Button("Reset") {
                UserSettings.hfCacheDirectory = UserSettings.defaultHFCacheDirectory
                hfCacheDir = UserSettings.hfCacheDirectory
                ModelManager.shared.refreshDownloadedModels()
              }
              .font(.callout)
              .controlSize(.small)
              .help("Restore the default directory")
            }

            Button("Select...") {
              chooseCacheFolder()
            }
            .font(.callout)
            .controlSize(.small)
          }
          .padding(.top, 4)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 440)
    .fixedSize()
  }

  /// Opens a folder picker and updates the HF cache directory
  private func chooseCacheFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose a cache directory for AI models"
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

  /// Abbreviates path by replacing home directory with ~
  private func abbreviatedPath(_ url: URL) -> String {
    let path = url.path
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
      return "~" + path.dropFirst(home.count)
    }
    return path
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

#Preview {
  SettingsView()
}
