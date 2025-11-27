import Foundation
import os.log

/// Represents the current status of a model
enum ModelStatus: Equatable {
  case available
  case downloading(Progress)
  case installed
}

/// Manages the high-level state of available and downloaded models.
@MainActor
class ModelManager: NSObject {
  static let shared = ModelManager()

  var downloadedModels: [CatalogEntry] = []
  private var downloadedModelIds: Set<String> = []

  private let downloader = ModelDownloader.shared
  private let logger = Logger(subsystem: Logging.subsystem, category: "ModelManager")

  override init() {
    super.init()
    refreshDownloadedModels()
    addObservers()
  }

  /// Downloads a model by delegating to the downloader.
  func downloadModel(_ model: CatalogEntry) throws {
    try downloader.downloadModel(model)
  }

  /// Gets the current status of a model.
  func status(for model: CatalogEntry) -> ModelStatus {
    if downloadedModelIds.contains(model.id) {
      return .installed
    }
    let downloadStatus = downloader.status(for: model)
    if case .downloading = downloadStatus {
      return downloadStatus
    }
    return .available
  }

  /// Safely deletes a downloaded model and its associated files.
  func deleteDownloadedModel(_ model: CatalogEntry) {
    let llamaServer = LlamaServer.shared
    if llamaServer.activeModelPath == model.modelFilePath {
      llamaServer.stop()
    }
    downloader.cancelModelDownload(model)

    let paths = model.allLocalModelPaths

    // Move file deletion to background queue to avoid blocking main thread
    Task.detached { [weak self] in
      do {
        // Delete files first, before modifying state
        for path in paths {
          if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
          }
        }

        // Only update state after successful deletion
        await MainActor.run {
          guard let self = self else { return }
          self.downloadedModelIds.remove(model.id)
          self.downloadedModels.removeAll { $0.id == model.id }
          NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
        }
      } catch {
        await MainActor.run {
          self?.logger.error("Failed to delete model: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Scans the local models directory and updates the list of downloaded models.
  func refreshDownloadedModels() {
    let modelsDir = CatalogEntry.modelStorageDirectory

    // Move directory reading to background queue to avoid blocking main thread
    Task.detached { [weak self] in
      guard let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path) else {
        await MainActor.run {
          guard let self = self else { return }
          self.downloadedModels = []
          self.downloadedModelIds = []
          NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
        }
        return
      }
      let fileSet = Set(files)

      // Optimization: Iterate over files instead of models to avoid O(N) catalog scan.
      // This scales with the number of installed models (small), not the catalog size (large).
      let downloaded = files.compactMap { file -> CatalogEntry? in
        guard let model = Catalog.modelsByFilename[file] else { return nil }

        if let additionalParts = model.additionalParts {
          for part in additionalParts {
            if !fileSet.contains(part.lastPathComponent) {
              return nil
            }
          }
        }
        return model
      }

      await MainActor.run {
        guard let self = self else { return }
        self.downloadedModels = downloaded
        self.downloadedModelIds = Set(downloaded.map { $0.id })
        NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
      }
    }
  }

  /// Cancels an ongoing download.
  func cancelModelDownload(_ model: CatalogEntry) {
    downloader.cancelModelDownload(model)
  }

  // MARK: - Convenience Methods

  /// Returns true if the model is installed (fully downloaded).
  func isInstalled(_ model: CatalogEntry) -> Bool {
    status(for: model) == .installed
  }

  /// Returns true if the model is currently downloading.
  func isDownloading(_ model: CatalogEntry) -> Bool {
    if case .downloading = status(for: model) { return true }
    return false
  }

  /// Returns the download progress if the model is currently downloading, nil otherwise.
  func downloadProgress(for model: CatalogEntry) -> Progress? {
    if case .downloading(let progress) = status(for: model) { return progress }
    return nil
  }

  private func addObservers() {
    // When the downloader finishes a set of files for a model, it posts this notification.
    // We observe it to refresh our list of fully downloaded models.
    NotificationCenter.default.addObserver(
      forName: .LBModelDownloadFinished,
      object: downloader,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshDownloadedModels()
      }
    }
  }
}
