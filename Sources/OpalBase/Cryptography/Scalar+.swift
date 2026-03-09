// Scalar+.swift

import Foundation

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
