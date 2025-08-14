import AppKit
import SwiftUI

struct ModelRow: View {
  let model: ModelCatalogEntry
  @Environment(ModelManager.self) var modelManager
  @Environment(LlamaServer.self) var llamaServer
  @State private var isHovered = false
  @State private var showMemoryPopover = false

  // Check if this model is compatible with system memory
  private var isModelCompatible: Bool {
    ModelCatalog.isModelCompatible(model)
  }

  // Get the current status and progress for this model
  private var modelStatus: ModelStatus {
    modelManager.getModelStatus(model)
  }


  var body: some View {
    HStack(alignment: .center, spacing: 4) {
      // Model brand logo positioned consistently for visual alignment
      Image(model.icon)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 18, height: 18)
        .padding(.trailing, 4)
        .opacity(0.9)

      // Model details section (name, size, capabilities)
      VStack(alignment: .leading, spacing: 4) {
        // Model name with family and capabilities
        HStack(spacing: 4) {
          Text(model.family)

          Text(model.variant)
        }

        // Model metadata: variant, quantization, and size
        HStack(spacing: 4) {
          Text(model.totalSize)
            .font(.system(size: 10, weight: .medium, design: .monospaced))

          // Show divider and capability icons only if model has special features
          if model.supportsVision || model.supportsAudio {
            Rectangle()
              .fill(Color.secondary.opacity(0.3))
              .frame(width: 1, height: 8)
              .padding(.horizontal, 2)
          }

          // Visual indicators for model capabilities
          if model.supportsVision {
            Image(systemName: "eyeglasses")
              .help("Vision")
          }

          if model.supportsAudio {
            Image(systemName: "waveform")
              .help("Audio")
          }

        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.secondary)
      }

      Spacer()

      // Memory warning for incompatible models (transient visual)
      if !isModelCompatible {
        Button(action: {
          showMemoryPopover.toggle()
        }) {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .frame(width: 32, height: 32)
        .popover(isPresented: $showMemoryPopover) {
          Text("This model requires more memory than your system has available.")
            .frame(width: 300)
            .padding()
        }
      }

      // Download progress display (shown when downloading)
      if case .downloading(let progress) = modelStatus {
        let _ = modelManager.downloadUpdateTrigger  // Force SwiftUI to observe updates
        let progressValue =
          progress.totalUnitCount > 0
          ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount) : 0.0
        
        // Custom progress indicator for better macOS compatibility
        ZStack {
          Circle()
            .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
          Circle()
            .trim(from: 0, to: progressValue)
            .stroke(Color.secondary, lineWidth: 2)
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.1), value: progressValue)
        }
        .frame(width: 16, height: 16)
      }

      // Dynamic action area - changes based on model state (downloaded, downloading, available)
      switch modelStatus {
      case .downloaded:
        // Controls for downloaded models: status indicator and run/stop button
        HStack(spacing: 8) {
          let isActive = llamaServer.isActive(model: model)

          if isActive {
            // Visual feedback for active model state
            if llamaServer.isLoading {
              // Spinner while model initializes
              ProgressView()
                .scaleEffect(0.5)
                .frame(width: 32, height: 32)
            } else {
              // Green indicator when model is loaded and ready
              Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .frame(width: 32, height: 32)
            }
          }

          // Interactive run/stop control
          Image(systemName: isActive ? "stop" : "play")
            .font(.system(size: 16))
            .frame(width: 32, height: 32)
        }
      case .downloading:
        // Simple stop button for models currently being downloaded
        HStack(spacing: 8) {
          Image(systemName: "multiply")
            .font(.system(size: 16))
            .frame(width: 32, height: 32)
        }
      case .available:
        // Download prompt for models not yet downloaded
        Image(systemName: "arrow.down")
          .symbolRenderingMode(.palette)
          .font(.system(size: 16))
          .frame(width: 32, height: 32)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
    .foregroundColor(isModelCompatible ? .primary : .secondary)
    .background(
      isHovered && isModelCompatible
        ? Color.primary.opacity(0.05) : Color.clear
    )
    .cornerRadius(6)
    .frame(maxWidth: .infinity)
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovered = hovering
    }
    .onTapGesture {
      handleRowClick()
    }
    // Context menu for downloaded models only (provides delete option)
    .contextMenu {
      if case .downloaded = modelStatus {
        Button(action: {
          showInFinder(model)
        }) {
          Label("Show in Finder", systemImage: "folder")
        }
        Divider()
        Button(action: {
          modelManager.deleteDownloadedModel(model)
        }) {
          Label("Delete", systemImage: "trash")
        }
      }
    }
  }

  // Central handler for all row interactions based on current model state
  private func handleRowClick() {
    switch modelStatus {
    case .downloaded:
      // Toggle server on/off for downloaded models
      llamaServer.toggle(model: model)
    case .downloading:
      // Cancel ongoing download
      modelManager.cancelModelDownload(model)
    case .available:
      // Begin download for available models only if compatible
      if isModelCompatible {
        modelManager.downloadModel(model)
      }
    // Do nothing for incompatible models
    }
  }

  private func showInFinder(_ model: ModelCatalogEntry) {
    let modelPath = model.modelFilePath
    NSWorkspace.shared.selectFile(modelPath, inFileViewerRootedAtPath: "")
  }
}
