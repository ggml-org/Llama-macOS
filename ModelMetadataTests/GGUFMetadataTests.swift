import Foundation
import XCTest

final class GGUFMetadataTests: XCTestCase {
  private func withGGUF(_ entries: [(String, UInt32, Data)], check: (String) throws -> Void) throws
  {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    append(UInt32(0x4655_4747))
    append(UInt32(3))
    append(UInt64(0))
    append(UInt64(entries.count))
    for (key, type, value) in entries {
      let bytes = Data(key.utf8)
      append(UInt64(bytes.count))
      data.append(bytes)
      append(type)
      data.append(value)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try check(url.path)
  }

  func testEncoderCombinations() throws {
    for vision in [false, true] {
      for audio in [false, true] {
        try withGGUF([
          ("clip.has_vision_encoder", 7, Data([vision ? 1 : 0])),
          ("clip.has_audio_encoder", 7, Data([audio ? 1 : 0])),
        ]) { path in
          XCTAssertEqual(
            GGUFMetadata.inputModalities(path: path),
            ["text"] + (vision ? ["image"] : []) + (audio ? ["audio"] : []))
        }
      }
    }
  }

  func testMissingKeysDoNotAssertMedia() throws {
    try withGGUF([]) { XCTAssertEqual(GGUFMetadata.inputModalities(path: $0), ["text"]) }
    try withGGUF([("clip.has_audio_encoder", 7, Data([1]))]) {
      XCTAssertEqual(GGUFMetadata.inputModalities(path: $0), ["text", "audio"])
    }
  }

  func testKeysMatchExactlyAndAudioGenerationIsSeparate() throws {
    try withGGUF([
      ("other.clip.has_vision_encoder", 7, Data([1])),
      ("other.clip.has_audio_encoder", 7, Data([1])),
      ("clip.has_gen_audio_encoder", 7, Data([1])),
    ]) { XCTAssertEqual(GGUFMetadata.inputModalities(path: $0), ["text"]) }
  }

  func testInvalidFlagDoesNotAssertCapabilities() throws {
    for (type, bytes) in [(UInt32(0), Data([1])), (UInt32(7), Data([2])), (UInt32(7), Data())] {
      try withGGUF([("clip.has_vision_encoder", type, bytes)]) {
        XCTAssertNil(GGUFMetadata.inputModalities(path: $0))
      }
    }
  }

  func testUnparseableFileDoesNotAssertCapabilities() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("not a projector".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    XCTAssertNil(GGUFMetadata.inputModalities(path: url.path))
  }

  func testExistingNumericSuffixLookups() throws {
    var context = UInt32(32768).littleEndian
    var layers = UInt32(2).littleEndian
    try withGGUF([
      ("qwen35.context_length", 4, withUnsafeBytes(of: &context) { Data($0) }),
      ("qwen35.nextn_predict_layers", 4, withUnsafeBytes(of: &layers) { Data($0) }),
    ]) { path in
      XCTAssertEqual(GGUFMetadata.contextLength(path: path) ?? nil, 32768)
      XCTAssertEqual(GGUFMetadata.hasEmbeddedMTPHead(path: path), true)
    }
  }
}
