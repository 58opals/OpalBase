// ScalarModel+.swift

import Foundation

enum ScalarPowModel {
    static let inversionExponentBits = makeExponentBits(
        from: UInt256Model(
            limbs: [
                0xbfd25e8cd036413f,
                0xbaaedce6af48a03b,
                0xfffffffffffffffe,
                0xffffffffffffffff
            ]
        )
    )
    
    private static func makeExponentBits(from exponent: UInt256Model) -> [Bool] {
        guard let mostSignificantBit = exponent.mostSignificantBitIndex else {
            return [false]
        }
        return stride(from: mostSignificantBit, through: 0, by: -1).map { exponent.testBit(at: $0) }
    }
}

extension ScalarModel {
    func pow(exponentBits: [Bool]) -> ScalarModel {
        var result = ScalarModel.one
        for bit in exponentBits {
            result = result.mulModN(result)
            if bit {
                result = result.mulModN(self)
            }
        }
        return result
    }
}

