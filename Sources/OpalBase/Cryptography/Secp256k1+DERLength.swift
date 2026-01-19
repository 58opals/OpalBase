// Secp256k1+DERLength.swift

import Foundation

extension Secp256k1 {
    enum DERLength {
        static func encode(_ length: Int) throws -> Data {
            guard length >= 0 else {
                throw Secp256k1.Error.derMalformed
            }
            if length < 0x80 {
                return Data([UInt8(length)])
            }
            var remainingLength = length
            var lengthBytes = [UInt8]()
            while remainingLength > 0 {
                lengthBytes.insert(UInt8(remainingLength & 0xff), at: 0)
                remainingLength >>= 8
            }
            guard lengthBytes.count <= 4 else {
                throw Secp256k1.Error.derMalformed
            }
            var result = Data()
            result.append(UInt8(0x80 | UInt8(lengthBytes.count)))
            result.append(contentsOf: lengthBytes)
            return result
        }
        
        static func decode(from data: Data, startingAt index: Int) throws -> (length: Int, nextIndex: Int) {
            guard index < data.count else {
                throw Secp256k1.Error.derMalformed
            }
            let firstByte = data[index]
            if firstByte < 0x80 {
                return (Int(firstByte), index + 1)
            }
            let count = Int(firstByte & 0x7f)
            guard count > 0, count <= 4 else {
                throw Secp256k1.Error.derMalformed
            }
            guard index + 1 + count <= data.count else {
                throw Secp256k1.Error.derMalformed
            }
            if data[index + 1] == 0x00 {
                throw Secp256k1.Error.derNonCanonical
            }
            var length = 0
            for byteIndex in 0..<count {
                length = (length << 8) | Int(data[index + 1 + byteIndex])
            }
            if length < 0x80 {
                throw Secp256k1.Error.derNonCanonical
            }
            return (length, index + 1 + count)
        }
    }
}
