import SwiftUI

/// A model the capture panel can target, in display order.
struct CaptureModel: Identifiable, Equatable {
  let id: String        // server model id, passed to the WebUI as `?model=`
  let name: String      // human-readable label for the chip / list
}

/// The Spotlight-style capture field shown inside the floating panel.
///
/// A prompt field plus a footer chip showing which model the prompt will run
/// against -- the target is always visible. Press ⌘K to open a filterable model
/// menu: the prompt stays visible above while a separate filter field takes over,
/// so you never lose sight of what you wrote. Type to filter, ↑/↓ to move, Enter
/// to pick; Esc closes the menu and returns to the prompt.
struct CaptureView: View {
  let models: [CaptureModel]
  /// Called with the entered text and the chosen model when the user submits.
  let onSubmit: (String, CaptureModel?) -> Void
  /// Called when the user cancels the whole capture.
  let onCancel: () -> Void
  /// Reports the view's desired height so the host panel can resize (the picker
  /// makes the panel taller).
  let onHeightChange: (CGFloat) -> Void

  private enum Field { case prompt, filter }

  @State private var prompt = ""
  @State private var filter = ""
  @State private var picking = false
  @State private var selected: Int      // index into `models` -- the target
  @State private var highlight = 0      // highlighted row in the filtered list
  @State private var hostWindow: NSWindow?
  @FocusState private var focus: Field?

  private static let fieldHeight: CGFloat = 64
  private static let footerHeight: CGFloat = 34
  private static let filterHeight: CGFloat = 42
  private static let rowHeight: CGFloat = 34
  private static let maxRows = 6        // list scrolls beyond this
  private static let cardGap: CGFloat = 8  // transparent gap between the two cards

  init(
    models: [CaptureModel],
    startIndex: Int,
    onSubmit: @escaping (String, CaptureModel?) -> Void,
    onCancel: @escaping () -> Void,
    onHeightChange: @escaping (CGFloat) -> Void
  ) {
    self.models = models
    self.onSubmit = onSubmit
    self.onCancel = onCancel
    self.onHeightChange = onHeightChange
    _selected = State(initialValue: models.indices.contains(startIndex) ? startIndex : 0)
  }

  private var currentModel: CaptureModel? {
    models.indices.contains(selected) ? models[selected] : nil
  }

  /// Models matching the current filter, in display order.
  private var filtered: [CaptureModel] {
    guard !filter.isEmpty else { return models }
    return models.filter { $0.name.localizedCaseInsensitiveContains(filter) }
  }

  var body: some View {
    VStack(spacing: Self.cardGap) {
      // Input card -- always present, showing what you wrote plus the target
      // model chip. Stays put when the selector opens below it.
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Image(systemName: "sparkle")
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
          TextField("Ask Llama\u{2026}", text: $prompt)
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .regular))
            .focused($focus, equals: .prompt)
            .onSubmit(submitPrompt)
        }
        .padding(.horizontal, 20)
        .frame(height: Self.fieldHeight)

        // The chip stays put whether or not the menu is open -- the input card's
        // layout is immutable. It also means the current model is always visible
        // here, so the menu below doesn't need to mark it.
        if let currentModel {
          footerChip(currentModel)
        }
      }
      .modifier(CardStyle())

      // Selector card -- a separate panel below the input, shown while picking.
      if picking {
        VStack(spacing: 0) {
          filterField
          modelList
        }
        .modifier(CardStyle())
      }
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .background(shortcutKeys)
    .background(WindowAccessor(window: $hostWindow))
    // Esc closes the picker (keeping the prompt); otherwise it cancels the panel.
    .onKeyPress(.escape) {
      if picking { closePicker(); return .handled }
      return .ignored
    }
    // ↑/↓ move the highlighted row while picking.
    .onKeyPress(.upArrow) { picking ? moveHighlight(-1) : .ignored }
    .onKeyPress(.downArrow) { picking ? moveHighlight(1) : .ignored }
    // Focus the prompt only once the panel is key -- setting @FocusState before
    // then is a no-op that also spends the transition, leaving the field
    // unfocused (see also `focusPromptIfKey`).
    .onAppear(perform: reportHeight)
    .onChange(of: hostWindow) { focusPromptIfKey() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
      if (note.object as? NSWindow) === hostWindow { focusPromptIfKey() }
    }
    .onChange(of: picking) { reportHeight() }
    .onChange(of: filter) { highlight = 0; reportHeight() }
    // Returning focus to the prompt (after closing the picker) makes AppKit
    // select all its text by default. Collapse that to a caret at the end so the
    // user can keep typing where they left off.
    .onChange(of: focus) { if focus == .prompt { movePromptCaretToEnd() } }
  }

  // MARK: - Subviews

  private func footerChip(_ model: CaptureModel) -> some View {
    HStack(spacing: 8) {
      Text(model.name)
        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
      Spacer()
      Text("switch model")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
      keycap("\u{2318}")
      keycap("K")
    }
    .padding(.horizontal, 16)
    .frame(height: Self.footerHeight)
  }

  private var filterField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 13))
        .foregroundStyle(.tint)
      TextField("Filter models\u{2026}", text: $filter)
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .focused($focus, equals: .filter)
        .onSubmit { choose(highlight) }
      keycap("esc")
    }
    .padding(.horizontal, 18)
    .frame(height: Self.filterHeight)
  }

  private var modelList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 1) {
          ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, model in
            // No current-model marker here -- it's already shown in the input
            // card's chip above.
            HStack(spacing: 8) {
              Text(model.name)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(1)
              Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: Self.rowHeight)
            .background(
              RoundedRectangle(cornerRadius: 7)
                .fill(idx == highlight ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear))
                .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
            .onTapGesture { choose(idx) }
            .id(idx)
          }
          if filtered.isEmpty {
            Text("No models match \u{201C}\(filter)\u{201D}")
              .font(.system(size: 12.5))
              .foregroundStyle(.tertiary)
              .frame(height: Self.rowHeight)
          }
        }
        .padding(.bottom, 4)
      }
      .frame(height: listHeight)
      .onChange(of: highlight) { proxy.scrollTo(highlight, anchor: .center) }
    }
  }

  private func keycap(_ label: String) -> some View {
    Text(label)
      .font(.system(size: 11, design: .monospaced))
      .foregroundStyle(.secondary)
      .frame(minWidth: 16)
      .padding(.vertical, 1)
      .padding(.horizontal, 4)
      .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
  }

  /// Hidden button carrying the ⌘K shortcut so it fires regardless of text focus.
  private var shortcutKeys: some View {
    Button("", action: openPicker)
      .keyboardShortcut("k", modifiers: .command)
      .opacity(0)
  }

  // MARK: - Layout

  private var listHeight: CGFloat {
    let rows = max(1, min(filtered.count, Self.maxRows))
    return CGFloat(rows) * Self.rowHeight + 4
  }

  private func reportHeight() {
    // The input card is immutable: field + chip whenever models are installed.
    let inputCard = Self.fieldHeight + (models.isEmpty ? 0 : Self.footerHeight)
    if picking {
      onHeightChange(inputCard + Self.cardGap + Self.filterHeight + listHeight)
    } else {
      onHeightChange(inputCard)
    }
  }

  // MARK: - Actions

  /// Move focus to the prompt, but only when the panel is key -- assigning
  /// @FocusState before the window is key does nothing and burns the transition,
  /// so we wait for key status (initial open, or regaining key). No-op while
  /// picking, so it never steals focus from the filter field.
  private func focusPromptIfKey() {
    guard !picking, hostWindow?.isKeyWindow == true else { return }
    focus = .prompt
  }

  private func openPicker() {
    guard !models.isEmpty, !picking else { return }
    filter = ""
    highlight = models.firstIndex { $0.id == currentModel?.id } ?? 0
    picking = true
    focus = .filter
  }

  private func closePicker() {
    picking = false
    filter = ""
    focus = .prompt
  }

  private func moveHighlight(_ delta: Int) -> KeyPress.Result {
    let count = filtered.count
    guard count > 0 else { return .handled }
    highlight = (highlight + delta + count) % count
    return .handled
  }

  private func choose(_ filteredIndex: Int) {
    guard filtered.indices.contains(filteredIndex),
      let realIndex = models.firstIndex(of: filtered[filteredIndex])
    else { return }
    selected = realIndex
    closePicker()
  }

  /// Collapse the prompt field's selection to a caret at the end. Runs after the
  /// focus change has installed the field editor as first responder (hence the
  /// async hop).
  private func movePromptCaretToEnd() {
    DispatchQueue.main.async {
      guard let editor = hostWindow?.firstResponder as? NSTextView else { return }
      let end = (editor.string as NSString).length
      editor.setSelectedRange(NSRange(location: end, length: 0))
    }
  }

  private func submitPrompt() {
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      onCancel()
      return
    }
    onSubmit(trimmed, currentModel)
  }
}

/// Reports the hosting `NSWindow` back to SwiftUI so we can react to its key
/// state (needed to focus the prompt only once the panel is actually key).
///
/// Reads the window from `viewDidMoveToWindow` -- AppKit calls that exactly when
/// the view is attached, so the window is always non-nil there. (A one-shot
/// `DispatchQueue.main.async` grab races the attachment and intermittently sees
/// `nil`, which left focus unset ~30% of the time.)
private struct WindowAccessor: NSViewRepresentable {
  @Binding var window: NSWindow?

  func makeNSView(context: Context) -> TrackingView {
    let view = TrackingView()
    view.onWindowChange = { newWindow in
      // Defer out of the layout pass to avoid mutating SwiftUI state mid-update.
      DispatchQueue.main.async { window = newWindow }
    }
    return view
  }

  func updateNSView(_ nsView: TrackingView, context: Context) {}

  final class TrackingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      onWindowChange?(window)
    }
  }
}

/// Frosted, rounded card chrome shared by the input and selector panels.
private struct CardStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .frame(maxWidth: .infinity)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
