import Foundation

struct ModelFamily {
  let name: String  // e.g. "Qwen3 2507"
  let series: String  // e.g. "qwen"
  let serverArgs: [String]?  // optional defaults for all models/builds
  let overheadMultiplier: Double  // overhead multiplier for file size
  let sizes: [ModelSize]

  init(
    name: String,
    series: String,
    serverArgs: [String]? = nil,
    overheadMultiplier: Double = 1.05,
    sizes: [ModelSize]
  ) {
    self.name = name
    self.series = series
    self.serverArgs = serverArgs
    self.overheadMultiplier = overheadMultiplier
    self.sizes = sizes.sorted { $0.parameterCount < $1.parameterCount }
  }

  var iconName: String {
    "ModelLogos/\(series.lowercased())"
  }

  var allModels: [CatalogEntry] {
    sizes.flatMap { size in
      ([size.build] + size.quantizedBuilds).map { build in
        Catalog.entry(family: self, size: size, build: build)
      }
    }
  }

  func selectableModels() -> [CatalogEntry] {
    // Group by size (e.g., "27B") to pick the preferred version
    let modelsBySize = Dictionary(grouping: allModels, by: { $0.size })

    return modelsBySize.values.compactMap { models in
      // First try to find a compatible model
      let compatibleModels = models.filter { $0.isCompatible() }
      if let bestCompatible = bestModel(in: compatibleModels) {
        return bestCompatible
      }

      // Fallback to best model regardless of compatibility
      return bestModel(in: models)
    }.sorted(by: CatalogEntry.displayOrder(_:_:))
  }

  private func bestModel(in models: [CatalogEntry]) -> CatalogEntry? {
    // Prefer full precision, fallback to quantized
    return models.first(where: { $0.isFullPrecision })
      ?? models.first(where: { !$0.isFullPrecision })
  }
}
