// FieldElement~InversionChain.swift

import Foundation

extension FieldElement {
    @inlinable
    func square(_ count: Int) -> FieldElement {
        var result = self
        for _ in 0..<count {
            result = result.square()
        }
        return result
    }
    
    @inlinable
    static func makePowerTwoToExponentMinusOne(_ element: FieldElement, exponent: Int) -> FieldElement {
        precondition(exponent >= 1)
        var result = element
        guard exponent > 1 else {
            return result
        }
        for _ in 1..<exponent {
            result = result.square().mul(element)
        }
        return result
    }
    
    @inlinable
    func invertFast() -> FieldElement {
        let powerTwoToOneMinusOne = self
        let powerTwoToTwoMinusOne = powerTwoToOneMinusOne.square().mul(powerTwoToOneMinusOne)
        let powerTwoToFourMinusOne = powerTwoToTwoMinusOne.square(2).mul(powerTwoToTwoMinusOne)
        let powerTwoToSixMinusOne = powerTwoToFourMinusOne.square(2).mul(powerTwoToTwoMinusOne)
        let powerTwoToEightMinusOne = powerTwoToFourMinusOne.square(4).mul(powerTwoToFourMinusOne)
        let powerTwoToSixteenMinusOne = powerTwoToEightMinusOne.square(8).mul(powerTwoToEightMinusOne)
        let powerTwoToThirtyTwoMinusOne = powerTwoToSixteenMinusOne.square(16).mul(powerTwoToSixteenMinusOne)
        let powerTwoToSixtyFourMinusOne = powerTwoToThirtyTwoMinusOne.square(32).mul(powerTwoToThirtyTwoMinusOne)
        let powerTwoToOneHundredTwentyEightMinusOne = powerTwoToSixtyFourMinusOne.square(64).mul(powerTwoToSixtyFourMinusOne)
        let powerTwoToOneHundredNinetyTwoMinusOne = powerTwoToOneHundredTwentyEightMinusOne.square(64).mul(powerTwoToSixtyFourMinusOne)
        let powerTwoToSevenMinusOne = powerTwoToSixMinusOne.square().mul(self)
        let powerTwoToFifteenMinusOne = powerTwoToEightMinusOne.square(7).mul(powerTwoToSevenMinusOne)
        let powerTwoToThirtyOneMinusOne = powerTwoToSixteenMinusOne.square(15).mul(powerTwoToFifteenMinusOne)
        let powerTwoToTwoHundredTwentyThreeMinusOne = powerTwoToOneHundredNinetyTwoMinusOne.square(31).mul(powerTwoToThirtyOneMinusOne)
        let upperExponent = powerTwoToTwoHundredTwentyThreeMinusOne.square(33)
        
        let powerTwoToTwentyTwoMinusOne = powerTwoToSixteenMinusOne.square(6).mul(powerTwoToSixMinusOne)
        var lowerExponent = powerTwoToTwentyTwoMinusOne.square(4)
        lowerExponent = lowerExponent.square().mul(self)
        lowerExponent = lowerExponent.square()
        lowerExponent = lowerExponent.square().mul(self)
        lowerExponent = lowerExponent.square().mul(self)
        lowerExponent = lowerExponent.square()
        lowerExponent = lowerExponent.square().mul(self)
        
        return upperExponent.mul(lowerExponent)
    }
}
