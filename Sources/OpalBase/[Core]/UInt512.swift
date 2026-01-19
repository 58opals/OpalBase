// UInt512.swift

import Foundation

struct UInt512: Sendable, Equatable {
    enum Error: Swift.Error, Equatable {
        case invalidDataLength(expected: Int, actual: Int)
    }
    
    var limbs: [UInt64]
    
    init(limbs: [UInt64]) {
        precondition(limbs.count == 8)
        self.limbs = limbs
    }
    
    init(data64: Data) throws {
        guard data64.count == 64 else {
            throw Error.invalidDataLength(expected: 64, actual: data64.count)
        }
        var newLimbs = [UInt64]()
        newLimbs.reserveCapacity(8)
        for index in 0..<8 {
            let offset = index * 8
            let limb = UInt512.makeUInt64FromBigEndianBytes(
                data: data64,
                offset: offset
            )
            newLimbs.append(limb)
        }
        limbs = newLimbs.reversed()
    }
    
    var data64: Data {
        var data = Data(count: 64)
        data.withUnsafeMutableBytes { buffer in
            for index in 0..<8 {
                let limb = limbs[7 - index].bigEndian
                buffer.storeBytes(of: limb, toByteOffset: index * 8, as: UInt64.self)
            }
        }
        return data
    }
    
    var isZero: Bool {
        limbs.allSatisfy { $0 == 0 }
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
