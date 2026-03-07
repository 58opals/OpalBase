// FieldElementModel+.swift

import Foundation

enum FieldPowModel {
    @usableFromInline static let squareRootExponentBits = makeExponentBits(
        from: UInt256Model(
            limbs: [
                0xffffffffbfffff0c,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0x3fffffffffffffff
            ]
        )
    )
    
    @usableFromInline static let legendreExponentBits = makeExponentBits(
        from: UInt256Model(
            limbs: [
                0xffffffff7ffffe17,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0x7fffffffffffffff
            ]
        )
    )
    
    @usableFromInline static let inversionExponentBits = makeExponentBits(
        from: UInt256Model(
            limbs: [
                0xfffffffefffffc2d,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0xffffffffffffffff
            ]
        )
    )
    
    @usableFromInline static func makeExponentBits(from exponent: UInt256Model) -> [Bool] {
        guard let mostSignificantBit = exponent.mostSignificantBitIndex else {
            return [false]
        }
        return stride(from: mostSignificantBit, through: 0, by: -1).map { exponent.testBit(at: $0) }
    }
}

extension FieldElementModel {
    @inlinable
    func pow(exponentBits: [Bool]) -> FieldElementModel {
        var result = FieldElementModel.one
        for bit in exponentBits {
            result = result.square()
            if bit {
                result = result.mul(self)
            }
        }
        return result
    }
    
    @inlinable
    func invert() -> FieldElementModel {
        return invertFast()
    }
    
    @inlinable
    func invertUsingExponentiation() -> FieldElementModel {
        pow(exponentBits: FieldPowModel.inversionExponentBits)
    }
}

