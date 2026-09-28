import SwiftUI

/// The Aliases tab -- names API clients can send as `"model"`, each pointed
/// at a model on this Mac.
///
/// Its own tab because it has its own audience: people calling the API from
/// their own code. Someone who only chats in the web UI can ignore all of it.
///
/// Listed by alias rather than by model because each alias points at exactly
/// one model: one picker per alias makes a conflict impossible to express,
/// where assigning names from a model's side would have to silently take a
/// name away from whichever model held it.
struct AliasesSettingsView: View {
  @State private var aliases = UserSettings.modelAliases
  @State private var models = ModelManager.shared.downloadedModels
  @State private var showingAddSheet = false

  var body: some View {
    Form {
      Section {
        Text(
          "Send an alias as \"model\" in an API request, in place of a model ID. Each Mac can point the same alias at a different model, so the same code runs on all of them."
        )
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Section {
        if aliases.isEmpty {
          Text("No aliases yet.")
            .foregroundStyle(.secondary)
        }

        ForEach(aliases, id: \.self) { alias in
          row(for: alias)
        }
      } footer: {
        HStack(alignment: .firstTextBaseline) {
          // Said up front because the restart unloads whatever is running --
          // from the user's seat that's a model vanishing mid-conversation.
          Text("Changes restart the server, which unloads the current model.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

          Spacer()

          Button("Add Alias…") { showingAddSheet = true }
            .controlSize(.small)
            // An alias has to point at something; with nothing installed the
            // sheet would open onto an empty picker.
            .disabled(models.isEmpty)
            .help(models.isEmpty ? "Install a model first." : "")
        }
      }
    }
    .formStyle(.grouped)
    // Installs and deletes happen while this tab is open (the menu stays
    // usable), and both change what the pickers can offer.
    .onReceive(NotificationCenter.default.publisher(for: .LBModelDownloadedListDidChange)) { _ in
      models = ModelManager.shared.downloadedModels
    }
    .sheet(isPresented: $showingAddSheet) {
      AddAliasSheet(models: models) { alias in
        save(aliases + [alias])
      }
    }
  }

  /// One alias: its name, the model it points at, and a remove button. The
  /// model is changed in place; renaming is remove-and-add, rare enough not to
  /// earn an editor.
  @ViewBuilder private func row(for alias: ModelAlias) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        // Monospaced: it's a literal the user types into their code.
        Text(alias.name)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)

        Spacer()

        ModelPicker(
          models: models,
          selection: Binding(
            get: { alias.modelId },
            set: { newId in
              save(aliases.map { $0 == alias ? ModelAlias(name: alias.name, modelId: newId) : $0 })
            })
        )

        Button {
          save(aliases.filter { $0 != alias })
        } label: {
          Image(systemName: "minus.circle")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(PressableStyle())
        .help("Remove this alias")
      }

      if let caution = caution(for: alias) {
        SettingCaution(text: caution)
      }
    }
  }

  /// Why `alias` isn't in effect even though it's listed, or nil if it is.
  ///
  /// Two ways that happens, and both look fine from this tab alone: the model
  /// was deleted (the alias is kept so it comes back with the model), or the
  /// user's own config replaces the model's aliases.
  private func caution(for alias: ModelAlias) -> String? {
    if !models.contains(where: { $0.id == alias.modelId }) {
      return "This model isn't installed, so requests for \(alias.name) fail until it is or you pick another."
    }
    if let value = ModelAliases.overridden(for: alias.modelId),
      !value.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) })
        .contains(alias.name)
    {
      return "\(UserModelOverrides.filename) sets this model's aliases to \(value), which replaces this one."
    }
    return nil
  }

  /// Writes through to defaults before updating the mirror, so the Advanced
  /// tab and the menu never render one change behind. The setter restarts the
  /// server with the regenerated `models.ini`.
  private func save(_ newValue: [ModelAlias]) {
    UserSettings.modelAliases = newValue
    aliases = UserSettings.modelAliases
  }
}

/// A picker over the installed models, in the menu's order and naming.
///
/// Keeps a selection that isn't installed as an entry of its own. Without it
/// the picker would show a blank control, which reads as "unset" when the
/// alias in fact still names a model -- one that may come back.
private struct ModelPicker: View {
  let models: [Model]
  @Binding var selection: String

  var body: some View {
    Picker("", selection: $selection) {
      ForEach(models, id: \.id) { model in
        Text(ModelIdParser.plainName(model.id, showTags: needsTags(model.id)))
          .tag(model.id)
      }
      if !models.contains(where: { $0.id == selection }) {
        Text("\(ModelIdParser.plainName(selection, showTags: true)) (not installed)")
          .tag(selection)
      }
    }
    .labelsHidden()
    .fixedSize()
    .help(selection)
  }

  /// Whether `id` would look identical to another installed model without
  /// its tags -- the same rule the menu uses to decide when to show them.
  private func needsTags(_ id: String) -> Bool {
    let key = ModelIdParser.displayKey(id)
    return models.filter { ModelIdParser.displayKey($0.id) == key }.count > 1
  }
}

/// Sheet for adding an alias: a name and the model it points at.
private struct AddAliasSheet: View {
  let models: [Model]
  let onSave: (ModelAlias) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var modelId = ""
  // Set only after a failed Save attempt, so the error isn't flashed while
  // the user is still typing; cleared as soon as the field changes again.
  @State private var error: String?

  private var trimmed: String {
    name.trimmingCharacters(in: .whitespaces)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Add alias")
          .font(.headline)

        Text("Requests that name this alias go to the model you pick.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // A plain grid rather than a Form: in a sheet, a Form claims spare
      // height and drops the picker's label.
      Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
        GridRow {
          Text("Name")
            .gridColumnAlignment(.trailing)
          // The placeholder doubles as the suggestion: the names people
          // reach for first are roles, not models.
          TextField("", text: $name, prompt: Text("code"))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .onSubmit { save() }
            .onChange(of: name) { _, _ in error = nil }
        }
        GridRow {
          Text("Model")
          ModelPicker(models: models, selection: $modelId)
        }
      }

      HStack {
        if let error {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

        Spacer()

        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)

        Button("Add") { save() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 420)
    .onAppear {
      // Start on the model that's running, if any: the likeliest reason to
      // add an alias is having just settled on a model for something.
      modelId = LlamaServer.shared.activeModelId.flatMap { active in
        models.first { $0.id == active }?.id
      } ?? models.first?.id ?? ""
    }
  }

  private func save() {
    if let message = ModelAliases.validationError(for: trimmed) {
      error = message
      return
    }
    onSave(ModelAlias(name: trimmed, modelId: modelId))
    dismiss()
  }
}
