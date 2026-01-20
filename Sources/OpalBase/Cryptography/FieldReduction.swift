// FieldReduction.swift

import Foundation

enum FieldReduction {
    @inlinable
    static func reduce(_ value: UInt512) -> UInt256 {
        var reducedLimbs: InlineArray<8, UInt64> = .init(repeating: 0)
        reducedLimbs[0] = value.limbs[0]
        reducedLimbs[1] = value.limbs[1]
        reducedLimbs[2] = value.limbs[2]
        reducedLimbs[3] = value.limbs[3]
        var upperLimbs: InlineArray<4, UInt64> = [
            value.limbs[4], value.limbs[5], value.limbs[6], value.limbs[7]
        ]
        reduceUpperLimbs(into: &reducedLimbs, upper: upperLimbs)
        while hasUpperLimbs(reducedLimbs) {
            upperLimbs = [
                reducedLimbs[4], reducedLimbs[5], reducedLimbs[6], reducedLimbs[7]
            ]
            reducedLimbs[4] = 0
            reducedLimbs[5] = 0
            reducedLimbs[6] = 0
            reducedLimbs[7] = 0
            reduceUpperLimbs(into: &reducedLimbs, upper: upperLimbs)
        }
        var result = UInt256(limbs: [
            reducedLimbs[0], reducedLimbs[1], reducedLimbs[2], reducedLimbs[3]
        ])
        if result.compare(to: Secp256k1.Constant.p) != .orderedAscending {
            result = result.subtracting(Secp256k1.Constant.p).difference
        }
        return result
    }
    
    @usableFromInline static func reduceUpperLimbs(
        into limbs: inout InlineArray<8, UInt64>,
        upper: InlineArray<4, UInt64>
    ) {
        if (upper[0] | upper[1] | upper[2] | upper[3]) == 0 {
            return
        }
        addShiftedUpper(upper, to: &limbs)
        addMultipliedUpper(upper, to: &limbs)
    }
    
    @usableFromInline static func addShiftedUpper(
        _ upper: InlineArray<4, UInt64>,
        to limbs: inout InlineArray<8, UInt64>
    ) {
        for index in 0..<4 {
            let value = upper[index]
            addValue(value << 32, to: &limbs, at: index)
            addValue(value >> 32, to: &limbs, at: index + 1)
        }
    }
    
    @usableFromInline static func addMultipliedUpper(
        _ upper: InlineArray<4, UInt64>,
        to limbs: inout InlineArray<8, UInt64>
    ) {
        let multiplier: UInt64 = 977
        for index in 0..<4 {
            let value = upper[index]
            let product = value.multipliedFullWidth(by: multiplier)
            addValue(product.low, to: &limbs, at: index)
            addValue(product.high, to: &limbs, at: index + 1)
        }
    }
    
    @usableFromInline static func addValue(
        _ value: UInt64,
        to limbs: inout InlineArray<8, UInt64>,
        at index: Int
    ) {
        guard value != 0 else {
            return
        }
        var carry = value
        var currentIndex = index
        while carry > 0, currentIndex < 8 {
            let (sum, overflow) = limbs[currentIndex].addingReportingOverflow(carry)
            limbs[currentIndex] = sum
            carry = overflow ? 1 : 0
            currentIndex += 1
        }
    }
    
    @usableFromInline static func hasUpperLimbs(_ limbs: InlineArray<8, UInt64>) -> Bool {
        (limbs[4] | limbs[5] | limbs[6] | limbs[7]) != 0
    }
}
