// ScalarMultiplication+Endomorphism.swift

import Foundation

extension ScalarMultiplication {
    @inlinable
    static func mulGWithEndomorphism(_ scalar: Scalar) -> JacobianPoint {
        let split = scalar.splitForEndomorphism()
        let firstDigits = SignedScalar128.makeWindowedNonAdjacentForm(split.firstScalar, width: windowedNonAdjacentFormWidth)
        let secondDigits = SignedScalar128.makeWindowedNonAdjacentForm(split.secondScalar, width: windowedNonAdjacentFormWidth)
        
        let maximumCount = max(firstDigits.count, secondDigits.count)
        guard maximumCount > 0 else {
            return .infinity
        }
        
        var result = JacobianPoint.infinity
        for index in stride(from: maximumCount - 1, through: 0, by: -1) {
            result = result.double()
            
            if index < firstDigits.count {
                result = addWindowedDigit(firstDigits[index], using: generatorOddMultiplesAffine, to: result)
            }
            if index < secondDigits.count {
                result = addWindowedDigit(secondDigits[index], using: generatorEndomorphismOddMultiplesAffine, to: result)
            }
        }
        return result
    }
    
    @inlinable
    static func addWindowedDigit(
        _ digit: Int8,
        using table: InlineArray<8, AffinePoint>,
        to point: JacobianPoint
    ) -> JacobianPoint {
        guard digit != 0 else {
            return point
        }
        let isNegative = digit < 0
        let magnitude = Int(isNegative ? -digit : digit)
        let tableIndex = magnitude >> 1
        let affinePoint = table[tableIndex]
        return point.addAffine(isNegative ? affinePoint.negated() : affinePoint)
    }
}
