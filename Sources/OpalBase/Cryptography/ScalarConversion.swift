// ScalarConversion.swift

import Foundation

enum ScalarConversion {
    static func makeScalarFromFieldElement(_ fieldElement: FieldElement) throws -> Scalar {
        let parsed = try UInt256(data32: fieldElement.data32)
        var reduced = parsed
        if reduced.compare(to: Secp256k1.Constant.n) != .orderedAscending {
            reduced = reduced.subtracting(Secp256k1.Constant.n).difference
        }
        return Scalar(unchecked: reduced)
    }
    
    static func makeReducedScalarFromDigest(_ digest32: Data) throws -> Scalar {
        let parsed = try UInt256(data32: digest32)
        var reduced = parsed
        if reduced.compare(to: Secp256k1.Constant.n) != .orderedAscending {
            reduced = reduced.subtracting(Secp256k1.Constant.n).difference
        }
        return Scalar(unchecked: reduced)
    }
    
    static func makeReducedDataFromDigest(_ digest32: Data) throws -> Data {
        let reducedScalar = try makeReducedScalarFromDigest(digest32)
        return reducedScalar.data32
    }
}
