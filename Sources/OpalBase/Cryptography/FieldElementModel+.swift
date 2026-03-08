// FieldElementModel+.swift

import Foundation

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
}
