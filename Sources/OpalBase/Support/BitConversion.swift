// BitConversion.swift

import Foundation

enum BitConversion {
    enum Error: Swift.Error, Equatable {
        case invalidValue
        case invalidPadding
        case invalidBitWidth
    }

    static func convertBits(_ data: [UInt8],
                            from fromBits: Int,
                            to toBits: Int,
                            pad: Bool) throws -> [UInt8] {
        guard fromBits > 0,
              toBits > 0,
              fromBits < Int.bitWidth,
              toBits < Int.bitWidth,
              fromBits + toBits - 1 < Int.bitWidth else {
            throw Error.invalidBitWidth
        }
        var accumulator = 0
        var bits = 0
        let maximumValue = (1 << toBits) - 1
        let maximumAccumulator = (1 << (fromBits + toBits - 1)) - 1
        var result: [UInt8] = .init()
        result.reserveCapacity((data.count * fromBits + toBits - 1) / toBits)

        for value in data {
            if (value >> fromBits) != 0 { throw Error.invalidValue }

            accumulator = ((accumulator << fromBits) | Int(value)) & maximumAccumulator
            bits += fromBits

            while bits >= toBits {
                bits -= toBits
                result.append(UInt8((accumulator >> bits) & maximumValue))
            }
        }

        if pad, bits > 0 {
            result.append(UInt8((accumulator << (toBits - bits)) & maximumValue))
        }

        if !pad {
            if bits >= fromBits { throw Error.invalidPadding }
            if ((accumulator << (toBits - bits)) & maximumValue) != 0 { throw Error.invalidPadding }
        }

        return result
    }
}
