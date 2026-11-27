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
struct GGUFMetadata {

  /// The header's scalar key-value pairs, in file order. Arrays (the tokenizer
  /// vocab, merges, ...) aren't kept -- nothing we read is an array -- but
  /// their keys are, as `.other`, so a presence check still sees them.
  private let entries: [(key: String, value: Value)]

  private enum Value {
    case int(Int)
    case bool(Bool)
    case string(String)
    /// Floats, arrays, and integers too large for `Int`: present, but not
    /// something any lookup below reads.
    case other
  }

  /// Parses the header of the GGUF at `path` in one pass, or returns nil when
  /// it can't be parsed. Every lookup below then reads from memory.
  ///
  /// Parse once per file and ask it everything: walking the header means
  /// stepping through the whole tokenizer vocab whenever a key is absent, and
  /// the cache scan runs on the main thread at launch -- where it used to walk
  /// each model's header 4-6 times, once per lookup.
  static func read(path: String) -> GGUFMetadata? {
    parse(path: path).map(GGUFMetadata.init(entries:))
  }

  /// Whether the model carries an embedded multi-token-prediction head, per
  /// its `<arch>.nextn_predict_layers` metadata key (the same key llama.cpp
  /// loads into `hparams.n_layer_nextn`). We match on the key suffix rather
  /// than resolving `general.architecture` first -- the key is namespaced per
  /// arch (`qwen35moe.nextn_predict_layers`, ...) but unique within a file. An
  /// absent key is a definitive "no head".
  var hasEmbeddedMTPHead: Bool {
    (int(forKeySuffix: ".nextn_predict_layers") ?? 0) > 0
  }

  /// The model's native (training) context window, per its
  /// `<arch>.context_length` metadata key -- the value llama.cpp loads into
  /// `hparams.n_ctx_train`. Like the MTP head above we match on the key suffix
  /// rather than resolving `general.architecture` first, since the key is
  /// arch-namespaced (`gemma3.context_length`, ...) but unique within a file.
  ///
  /// The leading dot in the suffix is load-bearing: the sibling key
  /// `<arch>.rope.scaling.original_context_length` ends in `_context_length`
  /// (underscore, not dot), so anchoring on `.context_length` excludes it.
  ///
  /// Nil means the key is genuinely absent, which means llama.cpp can't run the
  /// file at all: `llama-model.cpp` reads this key as required (unlike the
  /// optional hparams around it) for every arch but CLIP, so a clean absence
  /// marks a non-LLM GGUF -- e.g. speech-to-text models (`cohere_asr`, ...),
  /// which namespace their hparams under `stt.*` instead.
  var contextLength: Int? {
    int(forKeySuffix: ".context_length")
  }

  /// Whether this is a decision model -- one that answers typed questions with
  /// a probability per option via llama-server's `/v1/systemone` endpoint,
  /// rather than generating text. llama.cpp keys this off
  /// `<arch>.decision.type` (`common.cpp`), so we do too: present means a
  /// decision model, whatever its value. Suffix-matched like the keys above.
  var isDecisionModel: Bool {
    value(forKeySuffix: ".decision.type") != nil
  }

  /// A decision model's `<arch>.decision.type` value (e.g. `laya`, `kev`,
  /// `clef`) -- which of llama.cpp's scoring schemes it uses. Nil when the
  /// key is absent or isn't a string.
  var decisionType: String? {
    if case .string(let type) = value(forKeySuffix: ".decision.type") { return type }
    return nil
  }

  /// Whether this is an embedding model, per its `<arch>.pooling_type` key --
  /// how llama.cpp pools token states into one vector (`llama_pooling_type`:
  /// 1 mean, 2 cls, 3 last). Chat models don't carry the key. 4 (rank) marks a
  /// reranker, which scores pairs rather than embedding, so it isn't counted.
  var isEmbeddingModel: Bool {
    (1...3).contains(int(forKeySuffix: ".pooling_type") ?? 0)
  }

  /// The model's kind, from the two checks above. Decision is tested first:
  /// some decision models are built on encoders that may also carry a pooling
  /// type, and what they're served as is the decision endpoint.
  var kind: ModelKind {
    if isDecisionModel { return .decision }
    if isEmbeddingModel { return .embedding }
    return .chat
  }

  /// What a projector (`mmproj`) sidecar takes as input, per its
  /// `clip.has_vision_encoder` and `clip.has_audio_encoder` keys -- the flags
  /// llama.cpp reads to decide which media a model accepts. A projector can
  /// encode images, audio, or both (omni models), so its presence alone
  /// doesn't say which. An absent key means false.
  var projectorInputs: Model.MediaInputs {
    Model.MediaInputs(
      image: bool(forKeySuffix: "clip.has_vision_encoder") ?? false,
      audio: bool(forKeySuffix: "clip.has_audio_encoder") ?? false)
  }

  // MARK: - Lookups

  /// The value of the first key ending in `keySuffix`, or nil when there's no
  /// such key.
  private func value(forKeySuffix keySuffix: String) -> Value? {
    entries.first { $0.key.hasSuffix(keySuffix) }?.value
  }

  /// A numeric key's value; nil when the key is absent or isn't numeric. A
  /// bool counts as 0/1, as it did when values were read straight off disk.
  private func int(forKeySuffix keySuffix: String) -> Int? {
    switch value(forKeySuffix: keySuffix) {
    case .int(let value): return value
    case .bool(let value): return value ? 1 : 0
    default: return nil
    }
  }

  /// A bool key's value; nil when the key is absent or isn't a bool.
  private func bool(forKeySuffix keySuffix: String) -> Bool? {
    if case .bool(let value) = value(forKeySuffix: keySuffix) { return value }
    return nil
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

  /// Walks the KV section once, keeping every key and its scalar value. Nil
  /// when the header can't be parsed.
  private static func parse(path: String) -> [(key: String, value: Value)]? {
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

    var entries: [(key: String, value: Value)] = []
    for _ in 0..<kvCount {
      guard let key = cursor.readString(),
        let rawType: UInt32 = cursor.readInt(),
        let type = ValueType(rawValue: rawType),
        let value = cursor.readValue(of: type)
      else { return nil }
      entries.append((key, value))
    }
    return entries
  }

  /// Bounds-checked little-endian reader over the mapped file.
  private struct Cursor {
    let data: Data
    var offset: Int = 0

    /// Loads straight off the mapped bytes rather than going through
    /// `Data.copyBytes`. Skipping the tokenizer vocab (a ~250k-string array)
    /// means a quarter of a million of these calls per file, and Data's
    /// range machinery dominates at that count: measured over a 30-model
    /// cache, the header pass drops from 1.35s to 0.27s for identical
    /// results. `loadUnaligned` because GGUF packs values back to back with
    /// no padding.
    mutating func readInt<T: FixedWidthInteger>() -> T? {
      let size = MemoryLayout<T>.size
      guard offset + size <= data.count else { return nil }
      let value: T = data.withUnsafeBytes { raw in
        raw.loadUnaligned(fromByteOffset: offset, as: T.self)
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

    /// Reads a value of `type`, keeping scalars and stepping over the rest.
    /// Nil when the bytes run out or are malformed.
    mutating func readValue(of type: ValueType) -> Value? {
      switch type {
      case .bool:
        return (readInt() as UInt8?).map { .bool($0 != 0) }
      case .string:
        // Not `readString()`: its length cap and strict decoding are a key's
        // sanity checks, and a value that fails them (a huge chat template,
        // stray non-UTF-8 bytes) shouldn't make the whole header unparseable.
        guard let length: UInt64 = readInt(), length <= UInt64(data.count - offset) else {
          return nil
        }
        let range = (data.startIndex + offset)..<(data.startIndex + offset + Int(length))
        offset += Int(length)
        return String(data: data[range], encoding: .utf8).map(Value.string) ?? .other
      case .float32, .float64, .array:
        return skipValue(of: type) ? .other : nil
      case .uint64:
        // Read it all either way, so the cursor stays aligned on a value
        // that doesn't fit `Int`.
        return (readInt() as UInt64?).map { Int(exactly: $0).map(Value.int) ?? .other }
      default:
        return readIntValue(of: type).map(Value.int)
      }
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
