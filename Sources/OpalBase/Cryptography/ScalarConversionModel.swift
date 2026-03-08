// ScalarConversionModel.swift

import Foundation

enum ScalarConversionModel {
    static func makeScalarFromFieldElement(_ fieldElement: FieldElementModel) throws -> ScalarModel {
        let parsed = try UInt256Model(data32: fieldElement.data32)
        var reduced = parsed
        if reduced.compare(to: OpalBase.Cryptography.Secp256k1.Constant.n) != .orderedAscending {
            reduced = reduced.subtract(OpalBase.Cryptography.Secp256k1.Constant.n).difference
        }
        return ScalarModel(unchecked: reduced)
    }
    
    static func makeReducedScalarFromDigest(_ digest32: Data) throws -> ScalarModel {
        let parsed = try UInt256Model(data32: digest32)
        var reduced = parsed
        if reduced.compare(to: OpalBase.Cryptography.Secp256k1.Constant.n) != .orderedAscending {
            reduced = reduced.subtract(OpalBase.Cryptography.Secp256k1.Constant.n).difference
        }
        return ScalarModel(unchecked: reduced)
    }
    
    static func makeReducedDataFromDigest(_ digest32: Data) throws -> Data {
        let reducedScalar = try makeReducedScalarFromDigest(digest32)
        return reducedScalar.data32
    }
}
