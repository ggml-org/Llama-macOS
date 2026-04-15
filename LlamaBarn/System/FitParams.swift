import CommonCrypto
import Foundation
import os.log

/// Memory characteristics computed by llama-fit-params for a model.
/// Cached to disk so we don't re-run on every launch.
struct FitParams: Codable {
  /// KV-cache footprint for a 1k-token context, in bytes.
  /// Maps directly to CatalogEntry.ctxBytesPer1kTokens.
  let ctxBytesPer1kTokens: Int
}

/// Runs the llama-fit-params binary to determine a model's memory characteristics.
/// Used for sideloaded models that don't have hardcoded values in the catalog.
enum FitParamsRunner {

  private static let logger = Logger(subsystem: Logging.subsystem, category: "FitParamsRunner")

  /// Runs llama-fit-params on a model file and returns parsed memory params.
  /// Takes ~1s per model. Falls back to a conservative size-based estimate on failure.
  /// Supports cancellation — terminates the subprocess if the Task is cancelled.
  static func run(modelPath: String) async -> FitParams? {
    let fallback = fallbackParams(modelPath: modelPath)
    let binaryPath = Bundle.main.bundlePath + "/Contents/MacOS/llama-cpp/llama-fit-params"

    guard FileManager.default.fileExists(atPath: binaryPath) else {
      logger.error("llama-fit-params binary not found at \(binaryPath)")
      return fallback
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
      var stdoutData = Data()
      var stderrData = Data()
      let group = DispatchGroup()

      group.enter()
      DispatchQueue.global().async {
        stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
      }

      group.enter()
      DispatchQueue.global().async {
        stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        group.leave()
      }

      if group.wait(timeout: .now() + .seconds(30)) == .timedOut {
        logger.error("llama-fit-params timed out for \(modelPath)")
        if process.isRunning {
          process.terminate()
        }
        _ = group.wait(timeout: .now() + .seconds(2))
        if process.isRunning {
          kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        return fallback
      }

      process.waitUntilExit()

      guard process.terminationStatus == 0 else {
        let errOutput = String(decoding: stderrData, as: UTF8.self)
        // terminationStatus 15 = SIGTERM from cancellation, don't log as error
        if process.terminationStatus != 15 {
          logger.error(
            "llama-fit-params exited with status \(process.terminationStatus): \(errOutput.prefix(500))"
          )
        }
        return fallback
      }

      let output =
        String(decoding: stdoutData, as: UTF8.self)
        + String(decoding: stderrData, as: UTF8.self)

      return parseOutput(output) ?? fallback
    } onCancel: {
      // Terminate the subprocess when the parent task is cancelled
      if process.isRunning {
        process.terminate()
      }
    }
  }

  /// Parses the llama_memory_breakdown_print output.
  ///
  /// Expected format:
  /// ```
  /// llama_memory_breakdown_print: |   - MTL0 (Apple M1)    |  5461 = 5460 + (3961 =  1794 +    1650 +     517) + ... |
  /// llama_memory_breakdown_print: |   - Host               |                 2587 =   680 +    1084 +     823         |
  /// ```
  ///
  /// We extract: self = model + context + compute
  /// ctxBytesPer1kTokens = ((MTL0 context + Host context) / 128) * 1024 * 1024
  private static func parseOutput(_ output: String) -> FitParams? {
    let lines = output.components(separatedBy: "\n")
    let breakdownLines = lines.filter { $0.contains("llama_memory_breakdown_print") }

    // Pattern captures "self = model + context + compute" — four numbers
    let selfPattern = try! NSRegularExpression(
      pattern: #"(\d+)\s*=\s*(\d+)\s*\+\s*(\d+)\s*\+\s*(\d+)"#
    )

    var mtl0Ctx = 0
    var hostCtx = 0

    for line in breakdownLines {
      // Skip the header line
      if line.contains("memory breakdown") { continue }

      let isMtl0 = line.contains("MTL0")
      let isHost = line.contains("Host")
      guard isMtl0 || isHost else { continue }

      // For MTL0, extract the part inside parens: (self = model + context + compute)
      var searchStr = line
      if isMtl0 {
        let parenPattern = try! NSRegularExpression(
          pattern: #"\((\d+\s*=\s*\d+\s*\+\s*\d+\s*\+\s*\d+)\)"#
        )
        if let match = parenPattern.firstMatch(
          in: line, range: NSRange(line.startIndex..., in: line)
        ),
          let range = Range(match.range(at: 1), in: line)
        {
          searchStr = String(line[range])
        }
      }

      guard
        let match = selfPattern.firstMatch(
          in: searchStr, range: NSRange(searchStr.startIndex..., in: searchStr)
        )
      else {
        logger.warning("Could not parse memory breakdown from line: \(line)")
        continue
      }

      // Extract the context value (3rd number in "self = model + context + compute")
      if let ctxRange = Range(match.range(at: 3), in: searchStr),
        let ctx = Int(searchStr[ctxRange])
      {
        if isMtl0 {
          mtl0Ctx = ctx
        } else {
          hostCtx = ctx
        }
      }
    }

    // Both must be found for a valid result
    guard mtl0Ctx > 0 || hostCtx > 0 else {
      logger.error("Failed to parse memory breakdown from llama-fit-params output")
      return nil
    }

    // Total context memory at 128k, divide by 128 to get per-1k-token cost (MiB),
    // then convert to bytes
    let totalCtxMib = Double(mtl0Ctx + hostCtx) / 128.0
    let ctxBytesPer1kTokens = Int(totalCtxMib * 1_048_576.0)

    logger.info(
      "Fit params: ctx=\(mtl0Ctx)+\(hostCtx) MiB at 128k → \(ctxBytesPer1kTokens) bytes/1k tokens"
    )

    return FitParams(ctxBytesPer1kTokens: ctxBytesPer1kTokens)
  }

  /// Conservative fallback for sideloaded GGUFs when llama-fit-params cannot
  /// initialize Metal, emits unparseable output, or times out.
  private static func fallbackParams(modelPath: String) -> FitParams {
    let resolvedPath = URL(fileURLWithPath: modelPath).resolvingSymlinksInPath().path
    let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedPath)
    let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    let gb = Double(fileSize) / 1_000_000_000.0

    let mibPer1k: Int
    switch gb {
    case 25...:
      mibPer1k = 128
    case 10..<25:
      mibPer1k = 64
    case 5..<10:
      mibPer1k = 32
    case 2..<5:
      mibPer1k = 16
    default:
      mibPer1k = 8
    }

    logger.info(
      "Using fallback fit params for \(modelPath): \(mibPer1k) MiB per 1k tokens"
    )
    return FitParams(ctxBytesPer1kTokens: mibPer1k * 1_048_576)
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
