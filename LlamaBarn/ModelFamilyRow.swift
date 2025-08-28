import AppKit
import SwiftUI

struct ModelFamilyRow: View {
  let family: String
  let models: [ModelCatalogEntry]
  let icon: String
  @Environment(ModelManager.self) var modelManager
  @State private var isHovered = false

  private static let darkGreen = Color(red: 0.0, green: 0.5, blue: 0.0)

  private var sortedModels: [ModelCatalogEntry] {
    models.sorted { compareModelsBySize($0, $1) }
  }

  var body: some View {
    Menu {
      ForEach(sortedModels, id: \.id) { model in
        ModelMenuItem(model: model)
      }
    } label: {
      HStack(alignment: .top, spacing: 4) {
        // Model brand logo positioned consistently for visual alignment
        Image(icon)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 18, height: 18)
          .padding(.trailing, 4)
          .padding(.top, 2)
          .opacity(0.9)

        // Family name and variant chips
        VStack(alignment: .leading, spacing: 4) {
          Text(family)
            .foregroundColor(.primary)

          // Variant chips/tags
          HStack(spacing: 4) {
            ForEach(sortedModels, id: \.id) { model in
              let isDownloaded = modelManager.getModelStatus(model) == .downloaded
              let isCompatible = ModelCatalog.isModelCompatible(model)

              HStack(spacing: 2) {
                if isDownloaded {
                  Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(Self.darkGreen)
                }
                Text(model.variant + (model.simplifiedQuantization == "Q8" ? "+" : ""))
                  .font(.system(size: 9, weight: .medium, design: .monospaced))
              }
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .overlay(
                RoundedRectangle(cornerRadius: 4)
                  .stroke(
                    isDownloaded
                      ? Self.darkGreen.opacity(0.4)
                      : isCompatible
                        ? Color.secondary.opacity(0.3)
                        : Color.secondary.opacity(0.2),
                    lineWidth: 1
                  )
              )
              .foregroundColor(
                isDownloaded
                  ? Self.darkGreen
                  : isCompatible
                    ? .secondary
                    : .secondary.opacity(0.4)
              )
            }
          }
        }

        Spacer()

        // Menu indicator
        Image(systemName: "chevron.right")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .frame(width: 32, height: 32)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 8)
      .background(
        isHovered ? Color.primary.opacity(0.05) : Color.clear
      )
      .cornerRadius(6)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .onHover { hovering in
        isHovered = hovering
      }
    }
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
  }

  // Compare models by size (file size first, then parameters as tiebreaker)
  private func compareModelsBySize(_ lhs: ModelCatalogEntry, _ rhs: ModelCatalogEntry) -> Bool {
    if lhs.fileSizeMB != rhs.fileSizeMB {
      return lhs.fileSizeMB < rhs.fileSizeMB
    }
    return lhs.sizeInBillions < rhs.sizeInBillions
  }
}

struct ModelMenuItem: View {
  let model: ModelCatalogEntry
  @Environment(ModelManager.self) var modelManager

  // Check if this model is compatible with system memory
  private var isModelCompatible: Bool {
    ModelCatalog.isModelCompatible(model)
  }

  // Get the current status of this model
  private var modelStatus: ModelStatus {
    modelManager.getModelStatus(model)
  }

  var body: some View {
    Button(action: {
      handleAction()
    }) {
      HStack {
        // Show download status indicator
        switch modelStatus {
        case .downloaded:
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.green)
        case .downloading:
          Image(systemName: "arrow.down.circle")
            .font(.system(size: 10))
            .foregroundColor(.blue)
        case .available:
          Image(systemName: "arrow.down.circle")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }

        // Single line format that works better in menus
        Text(
          "\(model.displayName)\(model.quantization == "Q8_0" ? " (\(model.quantization))" : "") - \(model.totalSize)"
        )
        .foregroundColor(isModelCompatible ? .primary : .primary.opacity(0.5))

        // Show capability icons inline
        if model.supportsVision {
          Image(systemName: "eyeglasses")
            .font(.system(size: 8))
            .help("Vision")
        }

        if model.supportsAudio {
          Image(systemName: "waveform")
            .font(.system(size: 8))
            .help("Audio")
        }

        Spacer()
      }
    }
    .disabled(modelStatus == .downloaded || (!isModelCompatible && modelStatus == .available))
  }

  private func handleAction() {
    switch modelStatus {
    case .available:
      if isModelCompatible {
        modelManager.downloadModel(model)
      }
    case .downloading:
      modelManager.cancelModelDownload(model)
    case .downloaded:
      // Downloaded models are disabled, so this shouldn't be called
      break
    }
  }
}
