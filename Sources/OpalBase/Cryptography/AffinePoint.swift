// AffinePoint.swift

import Foundation

struct AffinePoint: Sendable, Equatable {
    let x: FieldElement
    let y: FieldElement
    
    var isOnCurve: Bool {
        let left = y.square()
        let right = x.square().mul(x).add(.seven)
        return left == right
    }
    
    func compressedEncoding33() -> Data {
        var output = Data()
        output.reserveCapacity(33)
        output.append(y.isOdd ? 0x03 : 0x02)
        output.append(x.data32)
        return output
    }
    
    func uncompressedEncoding65() -> Data {
        Data([0x04]) + x.data32 + y.data32
    }
    
    func negated() -> AffinePoint {
        AffinePoint(x: x, y: y.negate())
    }
    
    func applyingEndomorphism() -> AffinePoint {
        let beta = FieldElement(unchecked: Secp256k1.Constant.endomorphismBeta)
        return AffinePoint(x: beta.mul(x), y: y)
    }
}
