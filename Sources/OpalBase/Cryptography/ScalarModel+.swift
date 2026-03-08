// ScalarModel+.swift

import Foundation

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
