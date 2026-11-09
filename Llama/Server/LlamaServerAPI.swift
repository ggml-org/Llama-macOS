import Foundation
import os.log

/// Per-model load state as reported by llama-server's `/models` endpoint.
enum ModelLoadState: String, Equatable {
  case loaded
  case loading
  case sleeping
  case unloaded
  /// The model's last load attempt exited with an error (an unknown
  /// architecture on an older engine, a corrupt file, ...). The router reports
  /// this as `unloaded` plus `failed: true`, and keeps it until the next load
  /// attempt -- so the menu can say the load failed instead of silently
  /// showing an idle model.
  case failed
}

/// HTTP client for communicating with llama-server's REST API.
/// Encapsulates request building and response parsing for server endpoints.
struct LlamaServerAPI {
  private let logger = Logger(subsystem: Logging.subsystem, category: "LlamaServerAPI")

  // MARK: - Public API

  /// Requests the server to load a model by ID.
  /// Returns true if the request was sent successfully.
  func loadModel(id: String) async -> Bool {
    await post(endpoint: "models/load", body: ["model": id])
  }

  /// Requests the server to unload a model by ID.
  /// Returns true if the server acknowledged the request.
  func unloadModel(id: String) async -> Bool {
    await post(endpoint: "models/unload", body: ["model": id])
  }

  /// Asks the router server to re-read models.ini and reconcile its model list
  /// in place (`GET /models?reload=1`). The server only unloads models whose
  /// entry was removed or changed -- untouched models stay resident.
  /// Returns true if the server acknowledged the request.
  func reloadModels() async -> Bool {
    await get(endpoint: "models?reload=1") != nil
  }

  /// Fetches the current status of all models.
  /// Returns a dictionary mapping model IDs to their load state.
  /// Unknown or missing states are treated as `.unloaded`.
  func fetchModelStatuses() async -> [String: ModelLoadState]? {
    guard let data = await get(endpoint: "models") else { return nil }

    guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
      return nil
    }

    return response.data.reduce(into: [String: ModelLoadState]()) { dict, item in
      if item.status?.failed == true {
        dict[item.id] = .failed
      } else {
        dict[item.id] = item.status.flatMap { ModelLoadState(rawValue: $0.value) } ?? .unloaded
      }
    }
  }

  // MARK: - Private Helpers

  // Always the current effective host and port -- read live so a runtime change
  // (port, or a new network bind address) is picked up without recreating the
  // client. The host matters: with a specific bind address the server isn't on
  // loopback at all, so localhost would silently fail every request.
  private var baseUrl: String { "http://\(LlamaServer.localHost):\(LlamaServer.port)" }

  /// A session that never caches.
  ///
  /// Every endpoint here either reports live server state or has a side effect
  /// (`?reload=1`), so a cached response is always wrong -- and a cached 200 is
  /// worse than an error, because the caller reads it as "the server did the
  /// thing". `llama serve` sends no cache headers at all, which leaves the
  /// decision to CFNetwork's heuristics; the shared cache has been seen holding
  /// entries for these URLs. Opting out is cheaper than relying on that
  /// heuristic staying favourable.
  private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.urlCache = nil
    return URLSession(configuration: config)
  }()

  /// Sends a GET request and returns the response data.
  private func get(endpoint: String, timeout: TimeInterval = 2.0) async -> Data? {
    guard let url = URL(string: "\(baseUrl)/\(endpoint)") else { return nil }

    var request = URLRequest(url: url)
    request.timeoutInterval = timeout

    do {
      let (data, response) = try await Self.session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200
      else { return nil }
      return data
    } catch {
      return nil
    }
  }

  /// Sends a POST request with JSON body.
  /// Returns true if the request succeeded (2xx status).
  private func post(endpoint: String, body: [String: Any]) async -> Bool {
    guard let url = URL(string: "\(baseUrl)/\(endpoint)") else { return false }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    do {
      let (_, response) = try await Self.session.data(for: request)
      return (response as? HTTPURLResponse)?.statusCode == 200
    } catch {
      return false
    }
  }

  // MARK: - Response Types

  private struct ModelsResponse: Decodable {
    struct ModelData: Decodable {
      let id: String
      let status: ModelStatus?
    }
    struct ModelStatus: Decodable {
      let value: String
      /// Set (with `value` = "unloaded") when the model's instance exited
      /// with a non-zero code. Absent otherwise.
      let failed: Bool?
    }
    let data: [ModelData]
  }
}
