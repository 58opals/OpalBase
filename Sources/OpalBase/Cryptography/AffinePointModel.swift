// AffinePointModel.swift

import Foundation

struct AffinePointModel: Sendable, Equatable {
    let x: FieldElementModel
    let y: FieldElementModel
    
    var isOnCurve: Bool {
        let left = y.square()
        let right = x.square().mul(x).add(.seven)
        return left == right
    }
    
    func encodeCompressed33() -> Data {
        var output = Data()
        output.reserveCapacity(33)
        output.append(y.isOdd ? 0x03 : 0x02)
        output.append(x.data32)
        return output
    }
    
    func encodeUncompressed65() -> Data {
        Data([0x04]) + x.data32 + y.data32
    }
    
    func negate() -> AffinePointModel {
        AffinePointModel(x: x, y: y.negate())
    }
    
    func applyEndomorphism() -> AffinePointModel {
        let beta = FieldElementModel(unchecked: Secp256k1Model.Constant.endomorphismBeta)
        return AffinePointModel(x: beta.mul(x), y: y)
    }
}
