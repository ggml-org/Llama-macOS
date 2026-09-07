import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders a string as a QR code image.
///
/// Shared because the server's address is offered for scanning from two
/// places -- the menu's header and the Network settings tab -- which should
/// not disagree about what a scannable code looks like.
enum QRCode {
  /// The size both surfaces draw the code at.
  ///
  /// Shared rather than repeated because "big enough to scan" is one judgement,
  /// not two: a phone held a hand's width away reads this fine, and it's small
  /// enough to sit in a settings row without setting the card's height on its own.
  static let size: CGFloat = 90

  /// Renders `string` as a QR code.
  ///
  /// The generator emits one module per pixel, so the raw output is tiny and
  /// would come out blurred by interpolation -- scaling it up first keeps the
  /// edges hard, which is what a camera needs to lock onto.
  /// - Parameter dark: whether the code is being drawn on a dark surface, in
  ///   which case the modules are drawn light so they still read against it.
  /// - Parameter scale: the display's pixel density. The code is rendered at
  ///   that many pixels per point and then labelled with its size in points,
  ///   so a Retina screen gets real pixels instead of a point-sized bitmap
  ///   smeared across two of them -- and a QR code shows that smearing badly,
  ///   since its edges are the whole signal.
  static func image(for string: String, size: CGFloat, dark: Bool, scale: CGFloat) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    // Medium correction: a screen is a clean scanning surface, so the extra
    // redundancy of a higher level would only make the modules smaller.
    filter.correctionLevel = "M"

    guard let raw = filter.outputImage else { return nil }

    // The background is left clear so the code sits on whatever surface
    // draws it, and the modules follow the appearance: near-black on a light
    // surface, near-white on a dark one. Pure black on pure white is harsher
    // than the code needs -- a decoder cares about the reflectance difference
    // between modules and their immediate background, and either pairing
    // clears that bar with room to spare.
    //
    // Inverting is optional in the spec rather than guaranteed, so a light-on-
    // dark code can be refused by older phones and some scanner apps. Taken
    // knowingly: the phones that scan this belong to people running local
    // models on an Apple Silicon Mac, which is not a population carrying
    // decade-old hardware (checked on a Pixel 9a, the case least likely to
    // work). And both surfaces print the address in text beside the code, so
    // a refused scan costs a typed URL rather than a dead end.
    let falseColor = CIFilter.falseColor()
    falseColor.inputImage = raw
    falseColor.color0 =
      dark
      ? CIColor(red: 0.93, green: 0.93, blue: 0.94)
      : CIColor(red: 0.13, green: 0.13, blue: 0.14)
    falseColor.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)

    guard let output = falseColor.outputImage else { return nil }

    // The generator bakes a one-module quiet zone into its output. Cropping it
    // off makes the image's edge the code's edge, so the code lines up with
    // whatever it's laid out against instead of sitting visibly inset from it.
    // The quiet zone isn't lost -- both surfaces draw the code on a plain
    // background with far more than the four modules of clear space the spec
    // asks for, so the padding is the layout's to give, not the bitmap's.
    let trimmed = output.cropped(to: output.extent.insetBy(dx: 1, dy: 1))

    let pixels = size * scale
    let factor = pixels / trimmed.extent.width
    // `cropped(to:)` keeps the original origin, so the crop has to be moved
    // back to zero -- otherwise the offset scales up with everything else.
    let scaled = trimmed
      .transformed(by: CGAffineTransform(translationX: -trimmed.extent.minX, y: -trimmed.extent.minY))
      .transformed(by: CGAffineTransform(scaleX: factor, y: factor))

    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(rep)
    return image
  }
}
