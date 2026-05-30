// String+BitData.swift

import Foundation

extension String {
    enum BitDataConversionError: Swift.Error, Equatable {
        case invalidBit(Character)
    }

    func convertBitsToData() throws -> Data {
        let bitValues = try map { bit -> UInt8 in
            switch bit {
            case "0":
                return 0
            case "1":
                return 1
            default:
                throw BitDataConversionError.invalidBit(bit)
            }
        }

        return Data(try BitConversion.convertBits(bitValues, from: 1, to: 8, pad: true))
    }
}
