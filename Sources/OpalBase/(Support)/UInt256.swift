// UInt256.swift

import Foundation

struct UInt256 {
    enum Error: Swift.Error, Equatable {
        case invalidDataLength(expected: Int, actual: Int)
    }
    
    @usableFromInline var limbs: InlineArray<4, UInt64>
    
    @inlinable
    init(limbs: InlineArray<4, UInt64>) {
        self.limbs = limbs
    }
    
    init(limbs: [UInt64]) {
        precondition(limbs.count == 4)
        self.limbs = [limbs[0], limbs[1], limbs[2], limbs[3]]
    }
    
    @usableFromInline static let zero = UInt256(limbs: .init(repeating: 0))
    @usableFromInline static let one = UInt256(limbs: [1, 0, 0, 0])
    
    init(data32: Data) throws {
        guard data32.count == 32 else {
            throw Error.invalidDataLength(expected: 32, actual: data32.count)
        }
        var temporaryLimbs: InlineArray<4, UInt64> = .init(repeating: 0)
        data32.withUnsafeBytes { rawBuffer in
            for index in 0..<4 {
                let word = rawBuffer.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self)
                temporaryLimbs[3 - index] = UInt64(bigEndian: word)
            }
        }
        limbs = temporaryLimbs
    }
    
    @inlinable
    var data32: Data {
        var data = Data(count: 32)
        data.withUnsafeMutableBytes { buffer in
            for index in 0..<4 {
                let limb = limbs[3 - index].bigEndian
                buffer.storeBytes(of: limb, toByteOffset: index * 8, as: UInt64.self)
            }
        }
        return data
    }
    
    @inlinable
    func compare(to other: UInt256) -> ComparisonResult {
        for index in stride(from: 3, through: 0, by: -1) {
            if limbs[index] < other.limbs[index] {
                return .orderedAscending
            }
            if limbs[index] > other.limbs[index] {
                return .orderedDescending
            }
        }
        return .orderedSame
    }
    
    @inlinable
    var isZero: Bool {
        (limbs[0] | limbs[1] | limbs[2] | limbs[3]) == 0
    }
    
    @inlinable
    var isOne: Bool {
        limbs[0] == 1 && limbs[1] == 0 && limbs[2] == 0 && limbs[3] == 0
    }
    
    @inlinable
    var isLeastSignificantBitSet: Bool {
        (limbs[0] & 1) == 1
    }
    
    @inlinable
    var mostSignificantBitIndex: Int? {
        for index in stride(from: 3, through: 0, by: -1) {
            let limb = limbs[index]
            if limb != 0 {
                let leadingZeros = limb.leadingZeroBitCount
                return index * 64 + (63 - leadingZeros)
            }
        }
        return nil
    }
    
    @inlinable
    func bit(at index: Int) -> Bool {
        guard index >= 0, index < 256 else {
            return false
        }
        let limbIndex = index / 64
        let bitIndex = index % 64
        return (limbs[limbIndex] >> bitIndex) & 1 == 1
    }
    
    @inlinable
    func adding(_ other: UInt256) -> (sum: UInt256, carry: Bool) {
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
    func subtracting(_ other: UInt256) -> (difference: UInt256, borrow: Bool) {
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
    func multipliedFullWidth(by other: UInt256) -> UInt512 {
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
    func squaredFullWidth() -> UInt512 {
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

extension UInt256 {
    @inlinable
    func shiftedRightOne() -> UInt256 {
        var result = self
        result.shiftRightOne()
        return result
    }
    
    @inlinable
    mutating func shiftRightOne() {
        var carry: UInt64 = 0
        for index in stride(from: 3, through: 0, by: -1) {
            let limb = limbs[index]
            let nextCarry = limb & 1
            limbs[index] = (limb >> 1) | (carry << 63)
            carry = nextCarry
        }
    }
    
    @inlinable
    func subtractingSmall(_ value: UInt64) -> UInt256 {
        var result = self
        result.subtractSmall(value)
        return result
    }
    
    @inlinable
    mutating func subtractSmall(_ value: UInt64) {
        var borrow = value
        for index in 0..<4 {
            if borrow == 0 {
                break
            }
            let (difference, overflow) = limbs[index].subtractingReportingOverflow(borrow)
            limbs[index] = difference
            borrow = overflow ? 1 : 0
        }
    }
    
    @inlinable
    func addingSmall(_ value: UInt64) -> UInt256 {
        var result = self
        result.addSmall(value)
        return result
    }
    
    @inlinable
    mutating func addSmall(_ value: UInt64) {
        var carry = value
        for index in 0..<4 {
            if carry == 0 {
                break
            }
            let (sum, overflow) = limbs[index].addingReportingOverflow(carry)
            limbs[index] = sum
            carry = overflow ? 1 : 0
        }
    }
}

extension UInt256: Sendable {}
extension UInt256: Equatable {
    static func == (lhs: UInt256, rhs: UInt256) -> Bool {
        lhs.limbs[0] == rhs.limbs[0]
        && lhs.limbs[1] == rhs.limbs[1]
        && lhs.limbs[2] == rhs.limbs[2]
        && lhs.limbs[3] == rhs.limbs[3]
    }
}
