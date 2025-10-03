import Foundation
import Observation
import os.log

/// Represents the current status of a model
enum ModelStatus: Equatable {
  case available
  case downloading(Progress)
  case downloaded

  static func == (lhs: ModelStatus, rhs: ModelStatus) -> Bool {
    switch (lhs, rhs) {
    case (.available, .available), (.downloaded, .downloaded):
      return true
    case (.downloading(let lhsProgress), .downloading(let rhsProgress)):
      return lhsProgress === rhsProgress
    default:
      return false
    }
  }
}

/// Manages the high-level state of available and downloaded models.
@Observable
class Manager: NSObject {
  static let shared = Manager()

  var downloadedModels: [CatalogEntry] = []
  private var downloadedModelIds: Set<String> = []

  var hasActiveDownloads: Bool {
    !downloader.activeDownloads.isEmpty
  }

  private let downloader = Downloader.shared
  private let logger = Logger(subsystem: "app.llamabarn.LlamaBarn", category: "Manager")
  private var observers: [NSObjectProtocol] = []

  private override init() {
    super.init()
    refreshDownloadedModels()
    addObservers()
  }

  deinit {
    removeObservers()
  }

  /// Downloads a model by delegating to the downloader.
  func downloadModel(_ model: CatalogEntry) throws {
    try downloader.downloadModel(model)
  }

  /// Gets the current status of a model.
  func getModelStatus(_ model: CatalogEntry) -> ModelStatus {
    if downloadedModelIds.contains(model.id) {
      return .downloaded
    }
    let downloadStatus = downloader.getDownloadStatus(for: model)
    if case .downloading = downloadStatus {
      return downloadStatus
    }
    return .available
  }

  /// Checks if a model has been completely downloaded.
  func isModelDownloaded(_ model: CatalogEntry) -> Bool {
    return downloadedModelIds.contains(model.id)
  }

  /// Safely deletes a downloaded model and its associated files.
  func deleteDownloadedModel(_ model: CatalogEntry) {
    let llamaServer = LlamaServer.shared
    if llamaServer.activeModelPath == model.modelFilePath {
      llamaServer.stop()
    }
    downloader.cancelModelDownload(model)
    let wasTracked = downloadedModelIds.remove(model.id) != nil
    downloadedModels.removeAll { $0.id == model.id }
    NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)

    Task {
      do {
        for path in model.allLocalModelPaths {
          if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
          }
        }
        // Post a final notification after deletion is complete on disk
        NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
      } catch {
        _ = await MainActor.run {
          if wasTracked {
            self.downloadedModelIds.insert(model.id)
          }
          if !self.downloadedModels.contains(where: { $0.id == model.id }) {
            self.downloadedModels.append(model)
          }
        }
        NotificationCenter.default.post(name: .LBModelDownloadedListDidChange, object: self)
        logger.error("Failed to delete model: \(error.localizedDescription)")
      }
    }
  }

  /// Scans the local models directory and updates the list of downloaded models.
  func refreshDownloadedModels() {
    let modelsDir = CatalogEntry.getModelStorageDirectory()
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

  private func addObservers() {
    let center = NotificationCenter.default
    // When the downloader finishes a set of files for a model, it posts this notification.
    // We observe it to refresh our list of fully downloaded models.
    observers.append(
      center.addObserver(forName: .LBModelDownloadFinished, object: downloader, queue: .main) {
        [weak self] _ in
        self?.refreshDownloadedModels()
      }
    )
  }

  private func removeObservers() {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
  }
}
