import Foundation

/// Minimal reader for the GGUF key-value header.
///
/// GGUF files open with a small self-describing metadata section (magic,
/// version, tensor count, then typed key-value pairs) before the tensor data.
/// We parse just that section to answer questions the filename can't --
/// starting with embedded MTP heads, which some publishers (unsloth) ship
/// without any filename marker. The file is memory-mapped, so only the header
/// pages are ever touched even on multi-GB models.
///
/// The parser is deliberately fail-soft: any structural surprise (unknown
/// version, truncated header, unknown value type) returns nil rather than
/// throwing -- callers fall back to their filename heuristics. Misreading a
/// model must never block install or scan.
enum GGUFMetadata {

  /// Whether the GGUF at `path` carries an embedded multi-token-prediction
  /// head, per its `<arch>.nextn_predict_layers` metadata key (the same key
  /// llama.cpp loads into `hparams.n_layer_nextn`). We match on the key
  /// suffix rather than resolving `general.architecture` first -- the key is
  /// namespaced per arch (`qwen35moe.nextn_predict_layers`, ...) but unique
  /// within a file. Returns nil when the header can't be parsed.
  static func hasEmbeddedMTPHead(path: String) -> Bool? {
    // Outer nil = header unparseable (caller falls back to heuristics);
    // inner nil = header fine but key absent, a definitive "no head".
    guard let layers = intValue(forKeySuffix: ".nextn_predict_layers", path: path) else {
      return nil
    }
    return (layers ?? 0) > 0
  }

  // MARK: - Header parsing

  /// GGUF metadata value types, per the spec's `gguf_metadata_value_type`.
  /// Raw values are the on-disk type ids.
  private enum ValueType: UInt32 {
    case uint8 = 0, int8 = 1, uint16 = 2, int16 = 3
    case uint32 = 4, int32 = 5, float32 = 6, bool = 7
    case string = 8, array = 9
    case uint64 = 10, int64 = 11, float64 = 12
  }

  /// Scans the KV section for the first key ending in `keySuffix`. The double
  /// optional distinguishes the two nil-ish outcomes: outer nil = the header
  /// couldn't be parsed at all; `.some(nil)` = the header parsed cleanly but
  /// the key isn't there (or isn't numeric) -- a trustworthy absence.
  private static func intValue(forKeySuffix keySuffix: String, path: String) -> Int?? {
    // `.alwaysMapped` avoids reading the (potentially huge) file into memory;
    // parsing only faults in the header pages.
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
    else { return nil }

    var cursor = Cursor(data: data)

    // Magic "GGUF" (0x46554747 little-endian) + version. Versions 2 and 3
    // share the layout we parse (v1 used 32-bit counts and predates every
    // model we'd encounter; anything newer than 3 may have changed the
    // format, so fail soft rather than guess).
    guard let magic: UInt32 = cursor.readInt(), magic == 0x4655_4747,
      let version: UInt32 = cursor.readInt(), version == 2 || version == 3,
      let _: UInt64 = cursor.readInt(),  // tensor count (unused)
      let kvCount: UInt64 = cursor.readInt(),
      kvCount < 1_000_000  // sanity bound against corrupt headers
    else { return nil }

    for _ in 0..<kvCount {
      guard let key = cursor.readString(),
        let rawType: UInt32 = cursor.readInt(),
        let type = ValueType(rawValue: rawType)
      else { return nil }

      if key.hasSuffix(keySuffix) {
        return .some(cursor.readIntValue(of: type))
      }
      guard cursor.skipValue(of: type) else { return nil }
    }
    return .some(nil)
  }

  /// Bounds-checked little-endian reader over the mapped file.
  private struct Cursor {
    let data: Data
    var offset: Int = 0

    mutating func readInt<T: FixedWidthInteger>() -> T? {
      let size = MemoryLayout<T>.size
      guard offset + size <= data.count else { return nil }
      var value: T = 0
      _ = withUnsafeMutableBytes(of: &value) { dest in
        data.copyBytes(to: dest, from: (data.startIndex + offset)..<(data.startIndex + offset + size))
      }
      offset += size
      return T(littleEndian: value)
    }

    mutating func readString() -> String? {
      guard let length: UInt64 = readInt(), length < 1_000_000,
        offset + Int(length) <= data.count
      else { return nil }
      let range = (data.startIndex + offset)..<(data.startIndex + offset + Int(length))
      offset += Int(length)
      return String(data: data[range], encoding: .utf8)
    }

    mutating func skip(_ count: Int) -> Bool {
      guard offset + count <= data.count else { return false }
      offset += count
      return true
    }

    /// Reads a numeric value of `type` as Int; nil for non-numeric types.
    mutating func readIntValue(of type: ValueType) -> Int? {
      switch type {
      case .uint8: return (readInt() as UInt8?).map(Int.init)
      case .int8: return (readInt() as Int8?).map(Int.init)
      case .uint16: return (readInt() as UInt16?).map(Int.init)
      case .int16: return (readInt() as Int16?).map(Int.init)
      case .uint32: return (readInt() as UInt32?).map(Int.init)
      case .int32: return (readInt() as Int32?).map(Int.init)
      case .bool: return (readInt() as UInt8?).map(Int.init)
      case .uint64: return (readInt() as UInt64?).flatMap { Int(exactly: $0) }
      case .int64: return (readInt() as Int64?).flatMap { Int(exactly: $0) }
      case .float32, .float64, .string, .array: return nil
      }
    }

    /// Advances past a value of `type` without materializing it. Arrays are
    /// skipped element-wise since string elements have per-element lengths
    /// (the tokenizer vocab is a ~250k-string array, so this loop is the
    /// hot path -- each element is just a length read + seek).
    mutating func skipValue(of type: ValueType) -> Bool {
      switch type {
      case .uint8, .int8, .bool: return skip(1)
      case .uint16, .int16: return skip(2)
      case .uint32, .int32, .float32: return skip(4)
      case .uint64, .int64, .float64: return skip(8)
      case .string:
        guard let length: UInt64 = readInt(), length < UInt64(data.count) else { return false }
        return skip(Int(length))
      case .array:
        guard let rawElemType: UInt32 = readInt(),
          let elemType = ValueType(rawValue: rawElemType),
          let count: UInt64 = readInt(), count < UInt64(data.count)
        else { return false }
        // Fixed-size elements skip in one hop; strings/nested arrays iterate.
        switch elemType {
        case .uint8, .int8, .bool: return skip(Int(count))
        case .uint16, .int16: return skip(Int(count) * 2)
        case .uint32, .int32, .float32: return skip(Int(count) * 4)
        case .uint64, .int64, .float64: return skip(Int(count) * 8)
        case .string, .array:
          for _ in 0..<count {
            guard skipValue(of: elemType) else { return false }
          }
          return true
        }
      }
    }
  }
}
