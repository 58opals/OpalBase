// ScalarMultiplicationModel~GeneratorTable.swift

import Foundation

extension ScalarMultiplicationModel {
    @usableFromInline static let generatorMultiples8BitAffine: [AffinePointModel] = {
        let points = generatorMultiples8BitAffineChunk000_031
        + generatorMultiples8BitAffineChunk032_063
        + generatorMultiples8BitAffineChunk064_095
        + generatorMultiples8BitAffineChunk096_127
        + generatorMultiples8BitAffineChunk128_159
        + generatorMultiples8BitAffineChunk160_191
        + generatorMultiples8BitAffineChunk192_223
        + generatorMultiples8BitAffineChunk224_255
        precondition(points.count == 256)
        return points
    }()
}
