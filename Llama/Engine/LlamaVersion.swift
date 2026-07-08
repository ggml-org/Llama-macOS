import Foundation

/// A llama.cpp build version, parsed from `llama version` output like
/// `b9370-aa50b2c2a`. Comparison is by build number -- the monotonic `bXXXX`
/// counter llama.cpp bumps each release; the trailing commit sha is ignored.
struct LlamaVersion: Comparable, CustomStringConvertible {
  /// The build number, e.g. `9370` for `b9370`.
  let build: Int
  /// The original token as reported, e.g. `b9370-aa50b2c2a`.
  let raw: String

  /// Parses `llama version` output: an optional leading `b`, the build digits,
  /// then optionally `-<sha>`. Returns nil if no build number can be read.
  init?(parsing output: String) {
    guard let token = output.split(whereSeparator: { $0.isWhitespace }).first else {
      return nil
    }
    var digits = Substring(token)
    if let first = digits.first, first == "b" || first == "B" {
      digits = digits.dropFirst()
    }
    guard let build = Int(digits.prefix(while: { $0.isNumber })) else { return nil }
    self.build = build
    self.raw = String(token)
  }

  /// The clean build tag without the commit sha, e.g. `b9370`. For display.
  var tag: String { "b\(build)" }

  // Identity and ordering are by build number -- the commit sha is ignored, so a
  // pinned tag like `b9444` compares equal to a reported `b9444-<sha>`.
  static func == (lhs: LlamaVersion, rhs: LlamaVersion) -> Bool { lhs.build == rhs.build }
  static func < (lhs: LlamaVersion, rhs: LlamaVersion) -> Bool { lhs.build < rhs.build }

  var description: String { raw }
}
