// FieldElement+.swift

import Foundation

extension FieldElement {
    @inlinable
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
    
    @inlinable
    func invert() -> FieldElement {
        return invertFast()
    }
}
