import CommonCrypto
import Foundation
import os.log

/// Memory characteristics computed by llama-fit-params for a model.
/// Cached to disk so we don't re-run on every launch.
///
/// All fields are non-optional on purpose: when we add a new field, synthesized
/// Codable fails to decode old cache entries (keyNotFound), `FitParamsCache.get`
/// returns nil, and we re-run fit-params to produce a fresh entry. Don't switch
/// to `decodeIfPresent` or a custom `init(from:)` with defaults — that would
/// silently keep stale entries across upgrades.
struct FitParams: Codable {
  /// KV-cache footprint for a 1k-token context, in bytes.
  /// Maps directly to CatalogEntry.ctxBytesPer1kTokens.
  let ctxBytesPer1kTokens: Int
  /// Measured resident memory used by model weights + compute buffers, in bytes
  /// (summed across all devices in the final fit-params breakdown).
  /// 0 if unknown (e.g. fit-params failed). Maps to CatalogEntry.fitResidentBytes.
  let residentBytes: Int

  init(ctxBytesPer1kTokens: Int, residentBytes: Int = 0) {
    self.ctxBytesPer1kTokens = ctxBytesPer1kTokens
    self.residentBytes = residentBytes
  }
}

/// Runs the llama-fit-params binary to determine a model's memory characteristics.
/// Used for sideloaded models that don't have hardcoded values in the catalog.
enum FitParamsRunner {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "FitParamsRunner")

  /// Runs llama-fit-params on a model file and returns parsed memory params.
  /// Takes ~1s per model. Returns nil on failure (binary not found, parse error, etc).
  /// Supports cancellation — terminates the subprocess if the Task is cancelled.
  static func run(modelPath: String) async -> FitParams? {
    let binaryPath = Bundle.main.bundlePath + "/Contents/MacOS/llama-cpp/llama-fit-params"

    guard FileManager.default.fileExists(atPath: binaryPath) else {
      logger.error("llama-fit-params binary not found at \(binaryPath)")
      return nil
    }

    // Run with 128k context and debug verbosity to get the memory breakdown.
    // Running at 128k and dividing by 128 is more accurate than running at 1k
    // due to quantization effects at small context sizes.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = ["-m", modelPath, "-lv", "4", "-c", "131072"]

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

    // Use withTaskCancellationHandler to terminate the process if the task is cancelled.
    // Without this, cancelled tasks would leave zombie llama-fit-params processes running.
    return await withTaskCancellationHandler {
      // Read stdout and stderr concurrently to avoid pipe buffer deadlocks.
      // If we read them sequentially, the process can block writing to stderr
      // while we're blocked reading stdout (or vice versa), causing a hang.
      async let stdoutRead = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
      async let stderrRead = stderrPipe.fileHandleForReading.readDataToEndOfFile()

      let (stdout, stderr) = await (stdoutRead, stderrRead)
      process.waitUntilExit()

      guard process.terminationStatus == 0 else {
        let errOutput = String(decoding: stderr, as: UTF8.self)
        // terminationStatus 15 = SIGTERM from cancellation, don't log as error
        if process.terminationStatus != 15 {
          logger.error(
            "llama-fit-params exited with status \(process.terminationStatus): \(errOutput.prefix(500))"
          )
        }
        return nil
      }

      // Use String(decoding:as:) for lossy UTF-8 decoding — replaces invalid bytes
      // with U+FFFD instead of returning nil. llama-fit-params stderr can contain
      // raw tokenizer metadata with invalid UTF-8, which would cause strict decoding
      // to discard the entire output including valid breakdown lines.
      let output =
        String(decoding: stdout, as: UTF8.self)
        + String(decoding: stderr, as: UTF8.self)

      return parseOutput(output)
    } onCancel: {
      // Terminate the subprocess when the parent task is cancelled
      if process.isRunning {
        process.terminate()
      }
    }
  }

  /// Parses the llama_memory_breakdown_print output.
  ///
  /// fit-params prints one breakdown per search iteration; we only care about the last.
  /// Each breakdown has one row per device (MTL0, Host, and sometimes CPU_REPACK for
  /// MoE models whose experts spill off GPU). On Apple Silicon unified memory all
  /// devices share one physical RAM pool, so every row counts toward the budget.
  ///
  /// Row format (the numbers we care about are "self = model + context + compute"):
  /// ```
  /// |   - MTL0 (Apple M1)    |  5461 = 5460 + (3961 =  1794 +    1650 +     517) + ... |
  /// |   - Host               |                 2587 =   680 +    1084 +     823         |
  /// |   - CPU_REPACK         |                 3617 =  3617 +       0 +       0         |
  /// ```
  ///
  /// Weight memory = sum over devices of (model + compute). Compute buffers are
  /// resident during inference, so they belong with weights, not context.
  /// Per-1k-token cost = sum over devices of context / 128 (we run at 128k).
  private static func parseOutput(_ output: String) -> FitParams? {
    let lines = output.components(separatedBy: "\n")
    let breakdownLines = lines.filter { $0.contains("llama_memory_breakdown_print") }

    // Split into per-iteration groups, each starting with a "memory breakdown" header.
    var groups: [[String]] = []
    for line in breakdownLines {
      if line.contains("memory breakdown") {
        groups.append([])
      } else if !groups.isEmpty {
        groups[groups.count - 1].append(line)
      }
    }

    guard let lastGroup = groups.last, !lastGroup.isEmpty else {
      logger.error("Failed to find any memory breakdown in llama-fit-params output")
      return nil
    }

    // "self = model + context + compute" — four numbers inside the optional parens.
    let pattern = try! NSRegularExpression(
      pattern: #"(\d+)\s*=\s*(\d+)\s*\+\s*(\d+)\s*\+\s*(\d+)"#
    )

    var totalModelMib = 0
    var totalCtxMib = 0
    var totalComputeMib = 0

    // Each non-header line in the last group is a device row. Sum all of them —
    // don't filter by device name, since CPU_REPACK and future devices count too.
    // The MTL0 row wraps its breakdown in parens (to disambiguate from the leading
    // "total = free + self" sum), but the regex's `\d+ \+ \d+ \+ \d+` shape
    // only matches the inner "self = model + context + compute" form anyway —
    // the outer `5460 + (` breaks the digit-only pattern. So firstMatch is enough.
    for line in lastGroup {
      let range = NSRange(line.startIndex..., in: line)
      guard let match = pattern.firstMatch(in: line, range: range) else {
        continue  // not a device row (blank / divider)
      }

      if let modelRange = Range(match.range(at: 2), in: line),
        let ctxRange = Range(match.range(at: 3), in: line),
        let computeRange = Range(match.range(at: 4), in: line),
        let model = Int(line[modelRange]),
        let ctx = Int(line[ctxRange]),
        let compute = Int(line[computeRange])
      {
        totalModelMib += model
        totalCtxMib += ctx
        totalComputeMib += compute
      }
    }

    // Context is the primary signal; a breakdown with zero context is malformed.
    guard totalCtxMib > 0 else {
      logger.error("Failed to parse memory breakdown from llama-fit-params output")
      return nil
    }

    // Per-1k-token cost: fit-params was invoked at 128k, so divide total context by 128.
    let ctxMibPer1k = Double(totalCtxMib) / 128.0
    let ctxBytesPer1kTokens = Int(ctxMibPer1k * 1_048_576.0)

    // Weight memory: model + compute buffers (both resident during inference).
    let residentBytes = (totalModelMib + totalComputeMib) * 1_048_576

    logger.info(
      "Fit params: model=\(totalModelMib) MiB + compute=\(totalComputeMib) MiB, ctx=\(totalCtxMib) MiB at 128k → \(ctxBytesPer1kTokens) bytes/1k tokens, \(residentBytes) resident bytes"
    )

    return FitParams(ctxBytesPer1kTokens: ctxBytesPer1kTokens, residentBytes: residentBytes)
  }
}

/// Disk cache for llama-fit-params results.
/// Stored in ~/Library/Caches/{bundleId}/fitparams/ — the macOS-standard location
/// for derived, recreatable data. If the system purges the cache, we re-run.
enum FitParamsCache {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "FitParamsCache")

  /// Returns cached FitParams for a model ID, or nil if not cached.
  static func get(modelId: String) -> FitParams? {
    let path = cachePath(for: modelId)
    guard let data = try? Data(contentsOf: path) else { return nil }
    return try? JSONDecoder().decode(FitParams.self, from: data)
  }

  /// Stores FitParams for a model ID.
  static func set(_ params: FitParams, for modelId: String) {
    let path = cachePath(for: modelId)
    do {
      try FileManager.default.createDirectory(
        at: path.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(params)
      try data.write(to: path, options: .atomic)
    } catch {
      logger.error("Failed to cache fit params for \(modelId): \(error.localizedDescription)")
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
      .appendingPathComponent("fitparams")
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
