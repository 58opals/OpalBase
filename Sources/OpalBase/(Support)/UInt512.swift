// UInt512.swift

import Foundation

struct UInt512: Sendable, Equatable {
    enum Error: Swift.Error, Equatable {
        case invalidDataLength(expected: Int, actual: Int)
    }
    
    var limbs: InlineArray<8, UInt64>
    
    init(limbs: InlineArray<8, UInt64>) {
        self.limbs = limbs
    }
    
    init(limbs: [UInt64]) {
        precondition(limbs.count == 8)
        self.limbs = [
            limbs[0], limbs[1], limbs[2], limbs[3],
            limbs[4], limbs[5], limbs[6], limbs[7]
        ]
    }
    
    init(data64: Data) throws {
        guard data64.count == 64 else {
            throw Error.invalidDataLength(expected: 64, actual: data64.count)
        }
        var temporaryLimbs: InlineArray<8, UInt64> = .init(repeating: 0)
        data64.withUnsafeBytes { rawBuffer in
            for index in 0..<8 {
                let word = rawBuffer.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self)
                temporaryLimbs[7 - index] = UInt64(bigEndian: word)
            }
        }
        limbs = temporaryLimbs
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
        (limbs[0] | limbs[1] | limbs[2] | limbs[3] |
         limbs[4] | limbs[5] | limbs[6] | limbs[7]) == 0
    }
}
