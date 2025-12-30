import AppKit

/// Interactive header for catalog families.
final class FamilyHeaderView: ItemView {
  private let label = Theme.tertiaryLabel()
  private let descriptionLabel = Theme.tertiaryLabel()
  let family: String
  private let onAction: ((String) -> Void)?

  init(
    family: String,
    sizes: [String],
    description: String? = nil,
    isExpanded: Bool = false,
    onAction: ((String) -> Void)? = nil
  ) {
    self.family = family
    self.onAction = onAction
    super.init(frame: .zero)

    label.translatesAutoresizingMaskIntoConstraints = false
    label.attributedStringValue = Format.familyHeader(name: family, sizes: sizes)
    label.lineBreakMode = .byTruncatingTail

    descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
    descriptionLabel.stringValue = description ?? ""
    descriptionLabel.isHidden = description == nil
    descriptionLabel.maximumNumberOfLines = isExpanded ? 0 : 2
    descriptionLabel.lineBreakMode = .byWordWrapping
    descriptionLabel.cell?.wraps = true
    descriptionLabel.cell?.truncatesLastVisibleLine = true

    let textStack = NSStackView(views: [label])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 2
    textStack.translatesAutoresizingMaskIntoConstraints = false

    if let description = description, !description.isEmpty {
      textStack.addArrangedSubview(descriptionLabel)
    }

    contentView.addSubview(textStack)

    NSLayoutConstraint.activate([
      textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
      textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
      textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
    ])

    // Accessibility
    if onAction != nil {
      setAccessibilityElement(true)
      setAccessibilityRole(.button)
      setAccessibilityLabel(family)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var highlightEnabled: Bool { onAction != nil }

  override var intrinsicContentSize: NSSize {
    NSSize(width: Layout.menuWidth, height: NSView.noIntrinsicMetric)
  }

  override func mouseUp(with event: NSEvent) {
    super.mouseUp(with: event)
    // Only toggle if mouse is still within bounds (allows canceling by dragging away)
    if bounds.contains(convert(event.locationInWindow, from: nil)), let onAction = onAction {
      onAction(family)
    }
  }
}
