import Foundation
import os.log

/// Represents the current status of a model
enum ModelStatus: Equatable {
  case available
  case downloading(Progress)
  case installed

  static func == (lhs: ModelStatus, rhs: ModelStatus) -> Bool {
    switch (lhs, rhs) {
    case (.available, .available), (.installed, .installed):
      return true
    case (.downloading(let lhsProgress), .downloading(let rhsProgress)):
      // Custom equality: compare Progress by value, not reference identity.
      // Progress is a reference type (NSObject subclass), so default equality would compare
      // object identity (===), which would always return false when the same download's
      // Progress instance gets wrapped in new ModelStatus values during refresh cycles.
      // We need value-based comparison to detect actual progress changes for UI updates.
      return lhsProgress.completedUnitCount == rhsProgress.completedUnitCount
        && lhsProgress.totalUnitCount == rhsProgress.totalUnitCount
    default:
      return false
    }
  }
}

/// Manages the high-level state of available and downloaded models.
@MainActor
class ModelManager: NSObject {
  static let shared = ModelManager()

  var downloadedModels: [CatalogEntry] = []
  private var downloadedModelIds: Set<String> = []

  private let downloader = ModelDownloader.shared
  private let logger = Logger(subsystem: Logging.subsystem, category: "ModelManager")
  private let observer = NotificationObserver()

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

    do {
      // Delete files first, before modifying state
      for path in model.allLocalModelPaths {
        if FileManager.default.fileExists(atPath: path) {
          try FileManager.default.removeItem(atPath: path)
        }
      }

      // Only update state after successful deletion
      downloadedModelIds.remove(model.id)
      downloadedModels.removeAll { $0.id == model.id }
      NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
    } catch {
      logger.error("Failed to delete model: \(error.localizedDescription)")
    }
  }

  /// Scans the local models directory and updates the list of downloaded models.
  func refreshDownloadedModels() {
    let modelsDir = CatalogEntry.modelStorageDirectory
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path) else {
      self.downloadedModels = []
      self.downloadedModelIds = []
      NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
      return
    }
    let fileSet = Set(files)

    self.downloadedModels = Catalog.allEntries().filter { model in
      guard fileSet.contains(model.downloadUrl.lastPathComponent) else {
        return false
      }

      if let additionalParts = model.additionalParts {
        for part in additionalParts {
          if !fileSet.contains(part.lastPathComponent) {
            return false
          }
        }
      }
      return true
    }
    self.downloadedModelIds = Set(self.downloadedModels.map { $0.id })
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
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
    observer.observe(.LBModelDownloadFinished, object: downloader) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshDownloadedModels()
      }
    }
  }
}
