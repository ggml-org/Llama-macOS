import Foundation
import XCTest

final class CatalogInputsTests: XCTestCase {
  private func decode(_ fields: String) throws -> Catalog.Size {
    try JSONDecoder().decode(Catalog.Size.self, from: Data("{\(fields)\"builds\":[]}".utf8))
  }

  func testReleasedVisionCatalogNormalizesAtDecodeBoundary() throws {
    XCTAssertEqual(try decode("\"vision\":true,").inputModalities, ["text", "image"])
    XCTAssertEqual(try decode("\"vision\":false,").inputModalities, ["text"])
    XCTAssertEqual(try decode("").inputModalities, ["text"])
    XCTAssertEqual(try decode("\"inputModalities\":null,").inputModalities, ["text"])
  }

  func testExplicitInputsOverrideLegacyVision() throws {
    XCTAssertEqual(
      try decode("\"vision\":true,\"inputModalities\":[\"text\",\"audio\"],").inputModalities,
      ["text", "audio"])
    XCTAssertEqual(try decode("\"vision\":true,\"inputModalities\":[],").inputModalities, [])
  }

  func testUnknownInputsDoNotBreakDecoding() throws {
    XCTAssertEqual(
      try decode("\"inputModalities\":[\"text\",\"future-input\"],").inputModalities,
      ["text", "future-input"])
    XCTAssertThrowsError(try decode("\"inputModalities\":true,"))
  }

  func testEachDeclaredInputIsIndependent() {
    for (inputs, eye, subtitle) in [
      (["text"], false, "2 GB"),
      (["text", "image"], true, "2 GB"),
      (["text", "audio"], false, "2 GB  ∣  Audio input"),
      (["text", "video"], false, "2 GB  ∣  Video input"),
      (["text", "image", "audio", "video"], true, "2 GB  ∣  Audio input  ∣  Video input"),
    ] {
      let suggestion = Catalog.Suggestion(
        brand: "Example", repo: "example/model", quant: nil, sizeLabel: "2 GB",
        inputModalities: inputs, isGoodFirstModel: false)
      XCTAssertEqual(suggestion.hasVision, eye)
      XCTAssertEqual(suggestion.subtitle, subtitle)
    }
  }

  func testFirstModelLabelAndMissingSizeKeepExistingPresentation() {
    let suggestion = Catalog.Suggestion(
      brand: "Example", repo: "example/model", quant: nil, sizeLabel: nil,
      inputModalities: ["text", "audio"], isGoodFirstModel: true)
    XCTAssertEqual(suggestion.subtitle, "Good first model  ∣  Audio input")
  }

  func testOtherSizeAndBuildFieldsArePreserved() throws {
    let data = Data(
      """
      {"brand":"Example","featured":true,"sizes":[{
        "inputModalities":["text","video"],"maxMemGb":16,"goodFirstModel":true,
        "builds":[{"repo":"example/model","quant":"Q4_0","size":"2 GB"}]
      }]}
      """.utf8)
    let family = try JSONDecoder().decode(Catalog.Family.self, from: data)
    XCTAssertTrue(family.featured == true)
    let size = try XCTUnwrap(family.sizes.first)
    XCTAssertEqual(size.maxMemGb, 16)
    XCTAssertTrue(size.goodFirstModel == true)
    let build = try XCTUnwrap(size.builds.first)
    XCTAssertEqual(build.repo, "example/model")
    XCTAssertEqual(build.quant, "Q4_0")
    XCTAssertEqual(build.size, "2 GB")
  }
}
