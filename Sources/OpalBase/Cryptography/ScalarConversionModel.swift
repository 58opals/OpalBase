// ScalarConversionModel.swift

import Foundation

enum ScalarConversionModel {
    static func makeScalarFromFieldElement(_ fieldElement: FieldElementModel) throws -> ScalarModel {
        let parsed = try UInt256Model(data32: fieldElement.data32)
        var reduced = parsed
        if reduced.compare(to: Secp256k1Model.ConstantModel.n) != .orderedAscending {
            reduced = reduced.subtract(Secp256k1Model.ConstantModel.n).difference
        }
        return ScalarModel(unchecked: reduced)
    }
    
    static func makeReducedScalarFromDigest(_ digest32: Data) throws -> ScalarModel {
        let parsed = try UInt256Model(data32: digest32)
        var reduced = parsed
        if reduced.compare(to: Secp256k1Model.ConstantModel.n) != .orderedAscending {
            reduced = reduced.subtract(Secp256k1Model.ConstantModel.n).difference
        }
        return ScalarModel(unchecked: reduced)
    }
    
    static func makeReducedDataFromDigest(_ digest32: Data) throws -> Data {
        let reducedScalar = try makeReducedScalarFromDigest(digest32)
        return reducedScalar.data32
    }
}
