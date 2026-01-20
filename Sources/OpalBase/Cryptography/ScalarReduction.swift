// ScalarReduction.swift

import Foundation

enum ScalarReduction {
    @inlinable
    static func reduce(_ value: UInt512) -> UInt256 {
        var remainder = UInt256.zero
        var overflow = false
        let one = UInt256.one
        for bitIndex in stride(from: 511, through: 0, by: -1) {
            let shifted = shiftLeftOne(remainder)
            remainder = shifted.shifted
            overflow = shifted.overflow
            if bit(of: value, at: bitIndex) {
                let addition = remainder.adding(one)
                remainder = addition.sum
                overflow = overflow || addition.carry
            }
            if overflow || remainder.compare(to: Secp256k1.Constant.n) != .orderedAscending {
                remainder = remainder.subtracting(Secp256k1.Constant.n).difference
                overflow = false
            }
        }
        return remainder
    }
    
    @usableFromInline static func shiftLeftOne(_ value: UInt256) -> (shifted: UInt256, overflow: Bool) {
        var result: InlineArray<4, UInt64> = .init(repeating: 0)
        var carry: UInt64 = 0
        for index in 0..<4 {
            let limb = value.limbs[index]
            let newCarry = limb >> 63
            result[index] = (limb << 1) | carry
            carry = newCarry
        }
        return (UInt256(limbs: result), carry != 0)
    }
    
    @usableFromInline static func bit(of value: UInt512, at index: Int) -> Bool {
        guard index >= 0, index < 512 else {
            return false
        }
        let limbIndex = index / 64
        let bitIndex = index % 64
        return (value.limbs[limbIndex] >> bitIndex) & 1 == 1
    }
}
