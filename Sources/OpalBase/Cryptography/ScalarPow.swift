// ScalarPow.swift

import Foundation

enum ScalarPow {
    static let inversionExponentBits = makeExponentBits(
        from: UInt256(
            limbs: [
                0xbfd25e8cd036413f,
                0xbaaedce6af48a03b,
                0xfffffffffffffffe,
                0xffffffffffffffff
            ]
        )
    )
    
    private static func makeExponentBits(from exponent: UInt256) -> [Bool] {
        guard let mostSignificantBit = exponent.msb else {
            return [false]
        }
        return stride(from: mostSignificantBit, through: 0, by: -1).map { exponent.bit(at: $0) }
    }
}

extension Scalar {
    func pow(exponentBits: [Bool]) -> Scalar {
        var result = Scalar.one
        for bit in exponentBits {
            result = result.mulModN(result)
            if bit {
                result = result.mulModN(self)
            }
        }
        return result
    }
}
