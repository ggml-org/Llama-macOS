import AppKit
import Foundation

/// Submenu header that shows the model family "business card":
/// rounded-rect family icon, family name, and a short description.
final class FamilyInfoView: NSView {
  private let iconView = RoundedRectIconView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let descriptionLabel = NSTextField(labelWithString: "")
  private let container = NSView()

  init(familyName: String, iconName: String, blurb: String) {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    setup(familyName: familyName, iconName: iconName, blurb: blurb)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 70) }

  private func setup(familyName: String, iconName: String, blurb: String) {
    // Accessibility
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("\(familyName) info")

    container.translatesAutoresizingMaskIntoConstraints = false

    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.setImage(NSImage(named: iconName))
    iconView.isActive = false

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = Typography.primary
    titleLabel.stringValue = familyName
    titleLabel.lineBreakMode = .byTruncatingTail

    descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
    descriptionLabel.font = Typography.secondary
    descriptionLabel.textColor = .secondaryLabelColor
    descriptionLabel.stringValue = blurb
    descriptionLabel.lineBreakMode = .byWordWrapping

    let textStack = NSStackView(views: [titleLabel, descriptionLabel])
    textStack.orientation = .vertical
    textStack.spacing = 2
    textStack.alignment = .leading
    textStack.translatesAutoresizingMaskIntoConstraints = false

    let hStack = NSStackView(views: [iconView, textStack])
    hStack.orientation = .horizontal
    hStack.spacing = 8
    hStack.alignment = .top
    hStack.translatesAutoresizingMaskIntoConstraints = false

    addSubview(container)
    container.addSubview(hStack)

    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Metrics.outerHorizontalPadding),
      container.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.outerHorizontalPadding),
      container.topAnchor.constraint(equalTo: topAnchor),
      container.bottomAnchor.constraint(equalTo: bottomAnchor),

      iconView.widthAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),
      iconView.heightAnchor.constraint(equalToConstant: Metrics.iconBadgeSize),

      hStack.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: Metrics.innerHorizontalPadding),
      hStack.trailingAnchor.constraint(
        equalTo: container.trailingAnchor, constant: -Metrics.innerHorizontalPadding),
      hStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
      hStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
    ])
  }
}
