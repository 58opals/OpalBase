// UInt256Model+.swift

import Foundation

struct UInt256Model {
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

    @usableFromInline static let zero = UInt256Model(limbs: .init(repeating: 0))
    @usableFromInline static let one = UInt256Model(limbs: [1, 0, 0, 0])

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
    func compare(to other: UInt256Model) -> ComparisonResult {
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
    func testBit(at index: Int) -> Bool {
        guard index >= 0, index < 256 else {
            return false
        }
        let limbIndex = index / 64
        let bitIndex = index % 64
        return (limbs[limbIndex] >> bitIndex) & 1 == 1
    }
}

extension UInt256Model: Sendable {}
extension UInt256Model: Equatable {
    static func == (lhs: UInt256Model, rhs: UInt256Model) -> Bool {
        lhs.limbs[0] == rhs.limbs[0]
        && lhs.limbs[1] == rhs.limbs[1]
        && lhs.limbs[2] == rhs.limbs[2]
        && lhs.limbs[3] == rhs.limbs[3]
    }
}

