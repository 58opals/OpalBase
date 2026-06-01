// Data+Error.swift

import Foundation

extension Data {
    enum Error: Swift.Error {
        case cannotConvertHexadecimalStringToData
        case indexOutOfRange
    }
}

extension Data {
    static func unprefixedHexadecimalByteCount(_ hexadecimalString: String) -> Int? {
        let unicodeScalars = hexadecimalString.unicodeScalars
        guard unicodeScalars.count.isMultiple(of: 2) else { return nil }
        guard unicodeScalars.allSatisfy({ $0.hexadecimalNibble != nil }) else { return nil }

        return unicodeScalars.count / 2
    }

    init(hexadecimalString: String) throws {
        var byteArray = [UInt8]()
        let unicodeScalars = hexadecimalString.unicodeScalars
        let hasHexadecimalPrefix = hexadecimalString.hasPrefix("0x") || hexadecimalString.hasPrefix("0X")
        let hexadecimalStartIndex = hasHexadecimalPrefix
            ? unicodeScalars.index(unicodeScalars.startIndex, offsetBy: 2)
            : unicodeScalars.startIndex
        let hexadecimalScalars = unicodeScalars[hexadecimalStartIndex...]
        guard !hasHexadecimalPrefix || !hexadecimalScalars.isEmpty else {
            throw Error.cannotConvertHexadecimalStringToData
        }
        guard hexadecimalScalars.count.isMultiple(of: 2) else {
            throw Error.cannotConvertHexadecimalStringToData
        }
        byteArray.reserveCapacity(hexadecimalScalars.count / 2)
        
        var index = hexadecimalScalars.startIndex
        while index < hexadecimalScalars.endIndex {
            let nextIndex = hexadecimalScalars.index(after: index)
            guard let highNibble = hexadecimalScalars[index].hexadecimalNibble,
                  let lowNibble = hexadecimalScalars[nextIndex].hexadecimalNibble else {
                throw Error.cannotConvertHexadecimalStringToData
            }
            byteArray.append(highNibble << 4 | lowNibble)
            index = hexadecimalScalars.index(after: nextIndex)
        }
        
        self = Data(byteArray)
    }
    
    var hexadecimalString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
    
    func convertToBitString() -> String {
        return self.map { String($0, radix: 2).padLeft(to: 8) }.joined()
    }
    
    var reversedData: Data {
        return Data(self.reversed())
    }
}

extension Data {
    func extractValue<T: FixedWidthInteger>(from start: Data.Index) throws -> (value: T, newIndex: Data.Index) {
        let size = MemoryLayout<T>.size
        guard start >= self.startIndex, start + size <= self.endIndex else { throw Error.indexOutOfRange }
        var value: T = 0
        for i in 0..<size {
            value |= T(truncatingIfNeeded: self[start + i]) << (i * 8)
        }
        let newIndex = start + size
        
        return (T(littleEndian: value), newIndex)
    }
}

extension Data {
    static func push(_ buffer: Data) -> Data {
        var writer = Data.Writer()
        writer.reserveCapacity(5 + buffer.count)
        
        switch buffer.count {
        case 0...75:
            writer.writeByte(UInt8(buffer.count))
        case 76...255:
            writer.writeByte(ScriptOperationCode._PUSHDATA1.rawValue)
            writer.writeByte(UInt8(buffer.count))
        case 256...65535:
            writer.writeByte(ScriptOperationCode._PUSHDATA2.rawValue)
            writer.writeLittleEndian(UInt16(buffer.count))
        default:
            writer.writeByte(ScriptOperationCode._PUSHDATA4.rawValue)
            writer.writeLittleEndian(UInt32(buffer.count))
        }
        
        writer.writeData(buffer)
        return writer.data
    }
}
