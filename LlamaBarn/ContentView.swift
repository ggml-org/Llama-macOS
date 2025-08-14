import AppKit
import LaunchAtLogin
import Sparkle
import SwiftUI

struct ContentView: View {
  // Access shared instances through environment
  @Environment(ModelManager.self) var modelManager
  @Environment(LlamaServer.self) var llamaServer
  @Environment(UpdaterController.self) var updaterController
  @Environment(\.dismiss) private var dismiss

  @State private var isServerStatusHovered = false
  @State private var isMoreMenuHovered = false
  @State private var showAvailableInfo = false
  @Environment(\.colorScheme) private var colorScheme

  // Filter models by download status for display organization
  private var downloadedModels: [ModelCatalogEntry] {
    modelManager.downloadedModels
  }

  private var availableModels: [ModelCatalogEntry] {
    modelManager.availableModelCatalog.filter { model in
      !modelManager.isModelDownloaded(model)
    }
  }

  // Utility to open URLs in the default system browser
  private func openURL(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
  }


  var body: some View {
    // Main container for the popover content with organized model sections
    VStack(alignment: .leading, spacing: 0) {
      // Header with app title and settings menu
      HStack {
        Text("LlamaBarn")
          .font(.system(size: 14, weight: .regular))

        if llamaServer.memoryUsageMB > 0 {
          let memoryUsageGB = llamaServer.memoryUsageMB / 1024.0
          Text(String(format: "(%.2f GB)", memoryUsageGB))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.leading, 4)
        }

        Spacer()

        Menu {
          LaunchAtLogin.Toggle {
            Text("Launch at Login")
          }

          Divider()

          CheckForUpdatesButton(updater: updaterController.updater)

          Divider()

          VStack(alignment: .leading, spacing: 2) {
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
            Text("llama.cpp \(llamaServer.getLlamaCppVersion())")
          }
          .font(.caption)
          .foregroundColor(.secondary)

          Divider()

          Button("Quit") {
            NSApplication.shared.terminate(nil)
          }
          .keyboardShortcut("q", modifiers: .command)
        } label: {
          Image(systemName: "ellipsis")
            .foregroundColor(.secondary)
            .frame(width: 32, height: 32)
            .background(
              isMoreMenuHovered
                ? Color.primary.opacity(0.05) : Color.clear
            )
            .contentShape(Rectangle())
            .cornerRadius(4)
            .onHover { hovering in
              isMoreMenuHovered = hovering
            }
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 8)

      // Visual separator between header and content
      Divider()
        .padding(.horizontal, 8)

      // Organized model sections: Downloaded models first, then available for download
      VStack(spacing: 0) {
        // Downloaded models section - shows models ready to run
        if !downloadedModels.isEmpty {
          VStack(spacing: 4) {
            // Section header
            Text("Installed")
              .font(.subheadline)
              .foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 8)

            // List of downloaded models with run/stop controls
            VStack(spacing: 0) {
              ForEach(downloadedModels, id: \.id) { model in
                ModelRow(model: model)
              }
            }
          }
          .padding(.vertical, 8)

          // Separator between sections (only if both sections have content)
          if !availableModels.isEmpty {
            Divider()
              .padding(.horizontal, 8)
          }
        }

        // Available models section - shows models that can be downloaded
        if !availableModels.isEmpty {
          VStack(spacing: 4) {
            // Section header
            HStack {
              Text("Available")
              Button(action: {
                showAvailableInfo.toggle()
              }) {
                Image(systemName: "info.circle")
              }
              .buttonStyle(.plain)
              .popover(isPresented: $showAvailableInfo) {
                Text(
                  "We're showing the best model of each model family that would run your hardware."
                )
                // For some reason, using maxWidth truncates the content instead of wrapping it
                .frame(width: 300)
                .padding()
              }

              Spacer()
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)

            // List of models that can be downloaded
            VStack(spacing: 0) {
              ForEach(availableModels, id: \.id) { model in
                ModelRow(model: model)
              }
            }
          }
          .padding(.vertical, 8)
        }
      }

      // Visual separator between model list and server status
      Divider()
        .padding(.horizontal, 8)

      // Server status footer - shows current llama-server state and web interface link
      ServerStatusView(llamaServer: llamaServer, isHovered: $isServerStatusHovered) {
        if llamaServer.isRunning {
          openURL("http://localhost:\(LlamaServer.defaultPort)/")
          dismiss()
        }
      }
      .padding(.vertical, 8)

      // dev-only status information
      #if DEBUG
        Divider()
          .padding(.horizontal, 8)

        HStack {
          Image(systemName: "memorychip")
            .font(.system(size: 14))
            .frame(width: 18, height: 18)
            .padding(.trailing, 4)
            .opacity(0.9)

          Text(SystemMemory.formatMemory())
            .font(.system(size: 12))
            .foregroundColor(.secondary)

          Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
      #endif
    }
    .padding(.horizontal, 8)
    .frame(width: 300)
    .task {
      // Refresh downloaded models when view appears
      modelManager.refreshDownloadedModels()
    }
  }
}

#Preview {
  // SwiftUI preview for design-time development and testing
  // Create a mock UpdaterController for preview purposes
  let mockUpdater = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

  ContentView()
    .environment(UpdaterController(updater: mockUpdater.updater))
    .environment(ModelManager.shared)
    .environment(LlamaServer.shared)
}
