// FieldPow.swift

import Foundation

enum FieldPow {
    static let squareRootExponentBits = makeExponentBits(
        from: UInt256(
            limbs: [
                0xffffffffbfffff0c,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0x3fffffffffffffff
            ]
        )
    )
    
    static let legendreExponentBits = makeExponentBits(
        from: UInt256(
            limbs: [
                0xffffffff7ffffe17,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0x7fffffffffffffff
            ]
        )
    )
    
    static let inversionExponentBits = makeExponentBits(
        from: UInt256(
            limbs: [
                0xfffffffefffffc2d,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0xffffffffffffffff
            ]
        )
    )
    
    private static func makeExponentBits(from exponent: UInt256) -> [Bool] {
        guard let mostSignificantBit = exponent.mostSignificantBitIndex else {
            return [false]
        }
        return stride(from: mostSignificantBit, through: 0, by: -1).map { exponent.bit(at: $0) }
    }
}

extension FieldElement {
    func pow(exponentBits: [Bool]) -> FieldElement {
        var result = FieldElement.one
        for bit in exponentBits {
            result = result.square()
            if bit {
                result = result.mul(self)
            }
        }
        return result
    }
    
    func invert() -> FieldElement {
        pow(exponentBits: FieldPow.inversionExponentBits)
    }
}
