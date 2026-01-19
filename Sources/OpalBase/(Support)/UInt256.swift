// UInt256.swift

import Foundation

struct UInt256: Sendable, Equatable {
    enum Error: Swift.Error, Equatable {
        case invalidDataLength(expected: Int, actual: Int)
    }
    
    var limbs: [UInt64]
    
    init(limbs: [UInt64]) {
        precondition(limbs.count == 4)
        self.limbs = limbs
    }
    
    init(data32: Data) throws {
        guard data32.count == 32 else {
            throw Error.invalidDataLength(expected: 32, actual: data32.count)
        }
        var newLimbs = [UInt64]()
        newLimbs.reserveCapacity(4)
        for index in 0..<4 {
            let offset = index * 8
            let limb = UInt256.makeUInt64FromBigEndianBytes(
                data: data32,
                offset: offset
            )
            newLimbs.append(limb)
        }
        limbs = newLimbs.reversed()
    }
    
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
    
    var isZero: Bool {
        limbs.allSatisfy { $0 == 0 }
    }
    
    var isOne: Bool {
        limbs[0] == 1 && limbs[1] == 0 && limbs[2] == 0 && limbs[3] == 0
    }
    
    var lsb: Bool {
        (limbs[0] & 1) == 1
    }
    
    var msb: Int? {
        for index in stride(from: 3, through: 0, by: -1) {
            let limb = limbs[index]
            if limb != 0 {
                let leadingZeros = limb.leadingZeroBitCount
                return index * 64 + (63 - leadingZeros)
            }
        }
        return nil
    }
    
    func bit(at index: Int) -> Bool {
        guard index >= 0, index < 256 else {
            return false
        }
        let limbIndex = index / 64
        let bitIndex = index % 64
        return (limbs[limbIndex] >> bitIndex) & 1 == 1
    }
    
    func adding(_ other: UInt256) -> (sum: UInt256, carry: Bool) {
        var result = [UInt64](repeating: 0, count: 4)
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
    
    func subtracting(_ other: UInt256) -> (difference: UInt256, borrow: Bool) {
        var result = [UInt64](repeating: 0, count: 4)
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
    
    func multipliedFullWidth(by other: UInt256) -> UInt512 {
        var result = [UInt64](repeating: 0, count: 8)
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
    
    private static func makeUInt64FromBigEndianBytes(data: Data, offset: Int) -> UInt64 {
        var value: UInt64 = 0
        let base = data.startIndex + offset
        for index in 0..<8 {
            let byte = data[base + index]
            value = (value << 8) | UInt64(byte)
        }
        return value
    }
}
