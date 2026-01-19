// FieldReduction.swift

import Foundation

enum FieldReduction {
    static func reduce(_ value: UInt512) -> UInt256 {
        var reducedLimbs = [UInt64](repeating: 0, count: 8)
        for index in 0..<4 {
            reducedLimbs[index] = value.limbs[index]
        }
        reduceUpperLimbs(into: &reducedLimbs, upper: Array(value.limbs[4..<8]))
        while hasUpperLimbs(reducedLimbs) {
            let upper = Array(reducedLimbs[4..<8])
            for index in 4..<8 {
                reducedLimbs[index] = 0
            }
            reduceUpperLimbs(into: &reducedLimbs, upper: upper)
        }
        var result = UInt256(limbs: Array(reducedLimbs[0..<4]))
        if result.compare(to: Secp256k1.Constant.p) != .orderedAscending {
            result = result.subtracting(Secp256k1.Constant.p).difference
        }
        return result
    }
    
    private static func reduceUpperLimbs(into limbs: inout [UInt64], upper: [UInt64]) {
        guard !upper.allSatisfy({ $0 == 0 }) else {
            return
        }
        addShiftedUpper(upper, to: &limbs)
        addMultipliedUpper(upper, to: &limbs)
    }
    
    private static func addShiftedUpper(_ upper: [UInt64], to limbs: inout [UInt64]) {
        for index in 0..<upper.count {
            let value = upper[index]
            let lowerShift = value << 32
            let upperShift = value >> 32
            addValue(lowerShift, to: &limbs, at: index)
            addValue(upperShift, to: &limbs, at: index + 1)
        }
    }
    
    private static func addMultipliedUpper(_ upper: [UInt64], to limbs: inout [UInt64]) {
        let multiplier: UInt64 = 977
        for index in 0..<upper.count {
            let value = upper[index]
            let product = value.multipliedFullWidth(by: multiplier)
            addValue(product.low, to: &limbs, at: index)
            addValue(product.high, to: &limbs, at: index + 1)
        }
    }
    
    private static func addValue(_ value: UInt64, to limbs: inout [UInt64], at index: Int) {
        guard value != 0 else {
            return
        }
        var carry = value
        var currentIndex = index
        while carry > 0, currentIndex < limbs.count {
            let (sum, overflow) = limbs[currentIndex].addingReportingOverflow(carry)
            limbs[currentIndex] = sum
            carry = overflow ? 1 : 0
            currentIndex += 1
        }
    }
    
    private static func hasUpperLimbs(_ limbs: [UInt64]) -> Bool {
        for index in 4..<8 {
            if limbs[index] != 0 {
                return true
            }
        }
        return false
    }
}
