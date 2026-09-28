import Foundation
import OSLog

/// A stable name that API clients can send as `"model"` in place of a model
/// id, pointed at one installed model.
///
/// The point is portability: code written against `"model": "code"` runs
/// unchanged on every Mac, and each Mac decides which model answers to
/// `code` -- a big one where there's memory for it, a small one where there
/// isn't. So the mapping is deliberately per-device and never synced.
struct ModelAlias: Equatable, Hashable {
  var name: String
  var modelId: String
}

/// Turns the user's aliases into `alias` keys in `models.ini`, and keeps
/// them from ever producing a file the server won't start with.
///
/// The router resolves an alias to its model on every request (and lists it
/// under the model's `aliases` in `/models`), so there's no server-side
/// feature to build here -- only config to write.
enum ModelAliases {
  private static let logger = Logger(subsystem: Logging.subsystem, category: "ModelAliases")

  /// The preset key the router reads aliases from (`--alias`, comma-separated).
  static let presetKey = "alias"

  /// The names pointed at `modelId`, in the order the user added them.
  static func names(for modelId: String) -> [String] {
    UserSettings.modelAliases.filter { $0.modelId == modelId }.map(\.name)
  }

  /// Characters an alias may use.
  ///
  /// Narrow on purpose. Lowercase only, because the router matches names
  /// case-sensitively -- allowing `Code` next to `code` would give two names
  /// that read as one. No `/` or `:`, which every model id contains, so an
  /// alias can never collide with a model's id. No `,`, the separator in the
  /// preset value.
  private static let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")

  /// Why `name` can't be saved as an alias, or nil if it can.
  ///
  /// - Parameter replacing: the alias being edited, whose own name doesn't
  ///   count as taken.
  static func validationError(for name: String, replacing: ModelAlias? = nil) -> String? {
    if name.isEmpty {
      return "Enter a name."
    }
    if !name.allSatisfy(allowedCharacters.contains) {
      return "Use lowercase letters, digits, dots, dashes, or underscores."
    }
    let taken = UserSettings.modelAliases.filter { $0 != replacing }.map(\.name)
    if taken.contains(name) {
      return "There's already an alias named \(name)."
    }
    // Sections a user defined in models.user.ini are models too, under
    // whatever name they chose -- and the router refuses an alias that
    // matches a model's name.
    if UserModelOverrides.current.contains(where: { $0.name == name }) {
      return "\(UserModelOverrides.filename) defines a model named \(name)."
    }
    return nil
  }

  /// The aliases a `models.user.ini` entry sets for `modelId`, if it sets any.
  ///
  /// Overrides merge per key and the user always wins, so such an entry
  /// replaces the aliases set in the app rather than adding to them. The UI
  /// uses this to say so, instead of showing an alias that isn't in effect.
  static func overridden(for modelId: String) -> String? {
    UserModelOverrides.overriddenValue(presetKey, for: modelId)
  }

  /// Sets the `alias` key on a model's generated section. Applied before user
  /// overrides, so a user's own `alias` key replaces it like any other key.
  static func apply(to section: inout UserModelOverrides.Section) {
    let names = names(for: section.name)
    guard !names.isEmpty else { return }
    section.set(presetKey, names.joined(separator: ","))
  }

  /// Drops any alias the router would refuse, from the final merged sections.
  ///
  /// The router throws on an alias that matches a model name or another
  /// model's alias, and on a fresh start that takes the whole server down --
  /// every model, over one name. The app's own aliases can't conflict (the
  /// UI validates them), but a `models.user.ini` edit can introduce a clash
  /// at any time, and a server that won't start is a much worse outcome than
  /// one alias not resolving. First claim wins: generated sections come
  /// before user-only ones, so an alias set in the app keeps working.
  static func removeConflicts(from sections: [UserModelOverrides.Section])
    -> [UserModelOverrides.Section]
  {
    let modelNames = Set(sections.map(\.name))
    var claimed: Set<String> = []

    return sections.map { section in
      guard let value = section.pairs.first(where: { $0.key == presetKey })?.value else {
        return section
      }

      var kept: [String] = []
      for alias in value.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
      where !alias.isEmpty {
        if modelNames.contains(alias) || claimed.contains(alias) {
          logger.error(
            "Dropping alias '\(alias, privacy: .public)' for \(section.name, privacy: .public) -- already a model name or another model's alias"
          )
          continue
        }
        claimed.insert(alias)
        kept.append(alias)
      }

      var section = section
      if kept.isEmpty {
        section.remove(presetKey)
      } else {
        section.set(presetKey, kept.joined(separator: ","))
      }
      return section
    }
  }
}
