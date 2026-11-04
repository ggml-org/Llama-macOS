/// What a model does. The raw value is also its `tags` entry in `models.ini`,
/// which llama-server passes through to `/v1/models` -- the only place there a
/// client can tell a chat model from the others (all read text-in/text-out in
/// the listing's `architecture` modalities).
enum ModelKind: String, Codable {
  case chat
  case decision
  case embedding

  /// The row chip for a model that can't chat; nil for chat models, which are
  /// the default and need no label.
  var chipLabel: String? {
    switch self {
    case .chat: nil
    case .decision: "Decision"
    case .embedding: "Embedding"
    }
  }
}
