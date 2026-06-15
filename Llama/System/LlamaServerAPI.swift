import Foundation
import os.log

/// Per-model load state as reported by llama-server's `/models` endpoint.
enum ModelLoadState: String, Equatable {
  case loaded
  case loading
  case sleeping
  case unloaded
}

/// HTTP client for communicating with llama-server's REST API.
/// Encapsulates request building and response parsing for server endpoints.
struct LlamaServerAPI {
  let port: Int
  private let logger = Logger(subsystem: Logging.subsystem, category: "LlamaServerAPI")

  init(port: Int = LlamaServer.defaultPort) {
    self.port = port
  }

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

  /// Fetches the current status of all models.
  /// Returns a dictionary mapping model IDs to their load state.
  /// Unknown or missing states are treated as `.unloaded`.
  func fetchModelStatuses() async -> [String: ModelLoadState]? {
    guard let data = await get(endpoint: "models") else { return nil }

    guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
      return nil
    }

    return response.data.reduce(into: [String: ModelLoadState]()) { dict, item in
      dict[item.id] = item.status.flatMap { ModelLoadState(rawValue: $0.value) } ?? .unloaded
    }
  }

  // MARK: - Private Helpers

  private var baseUrl: String { "http://localhost:\(port)" }

  /// Sends a GET request and returns the response data.
  private func get(endpoint: String, timeout: TimeInterval = 2.0) async -> Data? {
    guard let url = URL(string: "\(baseUrl)/\(endpoint)") else { return nil }

    var request = URLRequest(url: url)
    request.timeoutInterval = timeout

    do {
      let (data, response) = try await URLSession.shared.data(for: request)
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
      let (_, response) = try await URLSession.shared.data(for: request)
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
    }
    let data: [ModelData]
  }
}
