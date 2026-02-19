// UInt256~Arithmetic.swift

import Foundation

extension UInt256 {
    @inlinable
    func add(_ other: UInt256) -> (sum: UInt256, carry: Bool) {
        var result: InlineArray<4, UInt64> = .init(repeating: 0)
        var carry: UInt64 = 0
        for index in 0..<4 {
            var sum = limbs[index]
            var overflow = false
            (sum, overflow) = sum.addingReportingOverflow(other.limbs[index])
            var overflowCarry = false
            (sum, overflowCarry) = sum.addingReportingOverflow(carry)
            result[index] = sum
            carry = (overflow || overflowCarry) ? 1 : 0
        }
        return (UInt256(limbs: result), carry != 0)
    }

    @inlinable
    func subtract(_ other: UInt256) -> (difference: UInt256, borrow: Bool) {
        var result: InlineArray<4, UInt64> = .init(repeating: 0)
        var borrow: UInt64 = 0
        for index in 0..<4 {
            var difference = limbs[index]
            var overflow = false
            (difference, overflow) = difference.subtractingReportingOverflow(other.limbs[index])
            var overflowBorrow = false
            (difference, overflowBorrow) = difference.subtractingReportingOverflow(borrow)
            result[index] = difference
            borrow = (overflow || overflowBorrow) ? 1 : 0
        }
        return (UInt256(limbs: result), borrow != 0)
    }

    @inlinable
    func multiplyFullWidth(by other: UInt256) -> UInt512 {
        var result: InlineArray<8, UInt64> = .init(repeating: 0)
        for leftIndex in 0..<4 {
            var carry: UInt64 = 0
            for rightIndex in 0..<4 {
                let (high, low) = limbs[leftIndex].multipliedFullWidth(by: other.limbs[rightIndex])
                let (sum, newCarry) = UInt256.multiplyAdd(
                    low: low,
                    addend: result[leftIndex + rightIndex],
                    carry: carry,
                    high: high
                )
                result[leftIndex + rightIndex] = sum
                carry = newCarry
            }
            var carryIndex = leftIndex + 4
            while carry > 0 {
                let (sum, overflow) = result[carryIndex].addingReportingOverflow(carry)
                result[carryIndex] = sum
                carry = overflow ? 1 : 0
                carryIndex += 1
            }
        }
        return UInt512(limbs: result)
    }

    @inlinable
    static func multiplyAdd(
        low: UInt64,
        addend: UInt64,
        carry: UInt64,
        high: UInt64
    ) -> (sum: UInt64, carry: UInt64) {
        var sum = addend
        var overflowLow = false
        (sum, overflowLow) = sum.addingReportingOverflow(low)
        var overflowCarry = false
        (sum, overflowCarry) = sum.addingReportingOverflow(carry)
        var newCarry = high
        if overflowLow {
            newCarry &+= 1
        }
        if overflowCarry {
            newCarry &+= 1
        }
        return (sum, newCarry)
    }

    @inlinable
    func squareFullWidth() -> UInt512 {
        var result: InlineArray<8, UInt64> = .init(repeating: 0)

        func addProduct(low: UInt64, high: UInt64, at index: Int) {
            var carry: UInt64 = 0
            let (sumLow, overflowLow) = result[index].addingReportingOverflow(low)
            result[index] = sumLow
            carry = overflowLow ? 1 : 0
            var sumHigh = result[index + 1]
            var overflowHigh = false
            (sumHigh, overflowHigh) = sumHigh.addingReportingOverflow(high)
            if carry > 0 {
                let (sumWithCarry, overflowCarry) = sumHigh.addingReportingOverflow(carry)
                sumHigh = sumWithCarry
                overflowHigh = overflowHigh || overflowCarry
            }
            result[index + 1] = sumHigh
            var carryIndex = index + 2
            var carryOut: UInt64 = overflowHigh ? 1 : 0
            while carryOut > 0, carryIndex < result.count {
                let (sum, overflow) = result[carryIndex].addingReportingOverflow(carryOut)
                result[carryIndex] = sum
                carryOut = overflow ? 1 : 0
                carryIndex += 1
            }
        }

        func addDoubledProduct(low: UInt64, high: UInt64, at index: Int) {
            let carryFromLow = low >> 63
            let carryFromHigh = high >> 63
            let doubledLow = low &<< 1
            let doubledHigh = (high &<< 1) | carryFromLow
            addProduct(low: doubledLow, high: doubledHigh, at: index)
            if carryFromHigh > 0 {
                var carryOut: UInt64 = 1
                var carryIndex = index + 2
                while carryOut > 0, carryIndex < result.count {
                    let (sum, overflow) = result[carryIndex].addingReportingOverflow(carryOut)
                    result[carryIndex] = sum
                    carryOut = overflow ? 1 : 0
                    carryIndex += 1
                }
            }
        }

        for index in 0..<4 {
            let limb = limbs[index]
            let (high, low) = limb.multipliedFullWidth(by: limb)
            addProduct(low: low, high: high, at: index * 2)
        }

        for leftIndex in 0..<4 {
            for rightIndex in (leftIndex + 1)..<4 {
                let (high, low) = limbs[leftIndex].multipliedFullWidth(by: limbs[rightIndex])
                addDoubledProduct(low: low, high: high, at: leftIndex + rightIndex)
            }
        }

        return UInt512(limbs: result)
    }
}
