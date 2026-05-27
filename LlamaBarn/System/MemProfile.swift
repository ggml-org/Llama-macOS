import CommonCrypto
import Foundation
import os.log

/// Per-model memory profile: parameters of an affine estimator that predicts
/// total memory at any context size. Currently produced by probing with
/// `llama-fit-params`, but the data is independent of how it's measured.
/// Cached to disk so we don't re-run on every launch.
///
/// All fields are non-optional on purpose: when we add a new field, synthesized
/// Codable fails to decode old cache entries (keyNotFound), `MemProfileCache.get`
/// returns nil, and we re-probe to produce a fresh entry. Don't switch to
/// `decodeIfPresent` or a custom `init(from:)` with defaults — that would
/// silently keep stale entries across upgrades.
struct MemProfile: Codable {
  /// Slope of the affine memory model, in bytes per 1k tokens.
  ///   mem(ctx) = residentBytes + ctxBytesPer1kTokens · ctx / 1000
  /// Maps directly to Model.ctxBytesPer1kTokens.
  let ctxBytesPer1kTokens: Int
  /// Intercept of the affine memory model, in bytes. Total footprint at ctx=0 —
  /// includes model weights, compute buffers, and any ctx-independent KV state
  /// (e.g. the per-layer local cache that SWA models like Gemma keep regardless
  /// of ctx). Maps to Model.residentBytes.
  /// 0 if unknown (e.g. probe failed).
  let residentBytes: Int
  /// Schema version. Bumping invalidates on-disk caches via the Codable
  /// keyNotFound mechanism documented at the top of this file.
  /// v2: switched from single-probe debug-table parse to two-probe -fitp affine
  ///     fit. Semantics of both above fields changed — v1 caches are discarded.
  let schemaVersion: Int

  init(ctxBytesPer1kTokens: Int, residentBytes: Int = 0) {
    self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
    self.residentBytes = residentBytes
    self.schemaVersion = 2
  }
}

/// Probes a model with the `llama-fit-params` binary to derive a `MemProfile`.
/// Used for sideloaded models that don't have hardcoded values in the catalog.
enum MemProfileRunner {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "MemProfileRunner")

  /// Probes a model at two context sizes and fits an affine memory model
  ///   mem(ctx) = a + b·ctx
  /// where `a` becomes residentBytes and `b·1000` becomes ctxBytesPer1kTokens.
  ///
  /// Why two probes, not one: memory is not purely linear in ctx. SWA models
  /// (Gemma family) keep a fixed-size per-layer local KV cache regardless of
  /// ctx, which shows up as a non-zero intercept (~174 MiB on Gemma 3 4B).
  /// Dividing a single 128k probe by 128 folds that intercept into the slope
  /// and mis-predicts small-ctx usage by multiple hundreds of MiB. A two-point
  /// affine fit recovers both terms correctly and degenerates cleanly to
  /// near-linear for dense models (where a ≈ 0).
  ///
  /// Takes ~2s per model (two probes). Returns nil on failure.
  /// Supports cancellation — terminates the subprocess if the Task is cancelled.
  static func run(modelPath: String) async -> MemProfile? {
    let binaryPath = Bundle.main.bundlePath + "/Contents/MacOS/llama-cpp/llama-fit-params"

    guard FileManager.default.fileExists(atPath: binaryPath) else {
      logger.error("llama-fit-params binary not found at \(binaryPath)")
      return nil
    }

    let ctxLo: UInt32 = 4096
    let ctxHi: UInt32 = 131072

    guard let loMib = await probeTotalMib(binary: binaryPath, modelPath: modelPath, ctx: ctxLo)
    else { return nil }
    guard let hiMib = await probeTotalMib(binary: binaryPath, modelPath: modelPath, ctx: ctxHi)
    else { return nil }

    // Affine fit: solve a + b·ctx_lo = lo, a + b·ctx_hi = hi.
    let dc = Double(ctxHi - ctxLo)
    let bPerToken = Double(hiMib - loMib) / dc  // MiB per token
    let aMib = Double(loMib) - bPerToken * Double(ctxLo)  // MiB at ctx=0

    // A negative slope means total memory went down as ctx grew — that's not
    // a real outcome, it signals a broken probe. Failing here routes the
    // caller to the file-size fallback, instead of silently producing a
    // "memory is ctx-independent" estimate that would accept any ctx and
    // risk OOM at runtime.
    guard bPerToken >= 0 else {
      logger.error(
        "Fit params: non-monotonic total (\(loMib) MiB at \(ctxLo) vs \(hiMib) MiB at \(ctxHi))"
      )
      return nil
    }

    // Clamp the intercept only — small negatives can appear from MiB rounding
    // at the probe points, or from a compute-buffer step that only shows up
    // at the high ctx. Overestimating the intercept is the safe direction.
    let aBytes = Int(max(aMib, 0) * 1_048_576.0)
    let bBytesPer1k = Int(bPerToken * 1000.0 * 1_048_576.0)

    logger.info(
      "Mem profile (affine): total(\(ctxLo))=\(loMib) MiB, total(\(ctxHi))=\(hiMib) MiB → a=\(aBytes) bytes, b=\(bBytesPer1k) bytes/1k"
    )

    return MemProfile(ctxBytesPer1kTokens: bBytesPer1k, residentBytes: aBytes)
  }

  /// Runs `llama-fit-params -c <ctx> -fitp on` and returns the total MiB
  /// footprint across all devices (sum of model + context + compute columns).
  ///
  /// `-fitp on` writes one line per device to stdout, e.g.:
  ///   MTL0 2402 2734 517
  ///   Host 680 0 538
  /// We sum every numeric column across every row — on Apple Silicon unified
  /// memory every row draws from the same physical RAM, so all rows count
  /// toward the same budget.
  private static func probeTotalMib(
    binary: String, modelPath: String, ctx: UInt32
  ) async -> Int? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["-m", modelPath, "-c", String(ctx), "-fitp", "on"]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      logger.error("Failed to launch llama-fit-params: \(error.localizedDescription)")
      return nil
    }

    return await withTaskCancellationHandler {
      // Read both pipes concurrently to avoid buffer-fill deadlocks. stderr
      // receives heavy log spam from the model load; we discard it.
      async let stdoutRead = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      async let stderrRead = stderrPipe.fileHandleForReading.readDataToEndOfFile()

      let (stdout, stderr) = await (stdoutRead, stderrRead)
      process.waitUntilExit()

      guard process.terminationStatus == 0 else {
        let errOutput = String(decoding: stderr, as: UTF8.self)
        // status 15 = SIGTERM from our cancellation handler, don't log
        if process.terminationStatus != 15 {
          logger.error(
            "llama-fit-params (ctx=\(ctx)) exited with status \(process.terminationStatus): \(errOutput.prefix(500))"
          )
        }
        return nil
      }

      let output = String(decoding: stdout, as: UTF8.self)

      // Each device row is `<name> <model> <context> <compute>` — a non-numeric
      // device name followed by three ints. We require that first-token-is-text
      // shape explicitly so a stray all-numeric line (if stderr ever leaks into
      // stdout, or the format changes) can't masquerade as a row.
      var totalMib = 0
      var rowCount = 0
      for line in output.split(separator: "\n") {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count == 4, Int(tokens[0]) == nil,
          let m = Int(tokens[1]), let c = Int(tokens[2]), let cp = Int(tokens[3])
        else { continue }
        totalMib += m + c + cp
        rowCount += 1
      }

      guard rowCount > 0 else {
        logger.error("Failed to parse -fitp output for ctx=\(ctx): \(output.prefix(500))")
        return nil
      }

      return totalMib
    } onCancel: {
      if process.isRunning {
        process.terminate()
      }
    }
  }
}

/// Disk cache for `MemProfile` results.
/// Stored in ~/Library/Caches/{bundleId}/MemProfile/ — the macOS-standard
/// location for derived, recreatable data. If the system purges the cache, we
/// re-probe.
enum MemProfileCache {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "MemProfileCache")

  /// Returns the cached MemProfile for a model ID, or nil if not cached.
  static func get(modelId: String) -> MemProfile? {
    let path = cachePath(for: modelId)
    guard let data = try? Data(contentsOf: path) else { return nil }
    return try? JSONDecoder().decode(MemProfile.self, from: data)
  }

  /// Stores a MemProfile for a model ID.
  static func set(_ profile: MemProfile, for modelId: String) {
    let path = cachePath(for: modelId)
    do {
      try FileManager.default.createDirectory(
        at: path.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(profile)
      try data.write(to: path, options: .atomic)
    } catch {
      logger.error("Failed to cache mem profile for \(modelId): \(error.localizedDescription)")
    }
  }

  // MARK: - Private

  /// Returns the cache file path for a model ID.
  /// Uses SHA256 of the model ID to avoid filesystem-unfriendly characters.
  private static func cachePath(for modelId: String) -> URL {
    let hash = sha256(modelId)
    return cacheDir.appendingPathComponent("\(hash).json")
  }

  private static var cacheDir: URL {
    let bundleId = Bundle.main.bundleIdentifier ?? "app.llamabarn.LlamaBarn"
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      .appendingPathComponent(bundleId)
      .appendingPathComponent("MemProfile")
  }

  private static func sha256(_ string: String) -> String {
    let data = Data(string.utf8)
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    _ = data.withUnsafeBytes { ptr in
      CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
  }
}
