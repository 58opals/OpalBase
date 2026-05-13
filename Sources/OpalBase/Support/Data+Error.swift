// Data+Error.swift

import Foundation

extension Data {
    enum Error: Swift.Error {
        case cannotConvertHexadecimalStringToData
        case indexOutOfRange
    }
}

extension Data {
    init(hexadecimalString: String) throws {
        var byteArray = [UInt8]()
        let unicodeScalars = hexadecimalString.unicodeScalars
        let hexadecimalStartIndex = hexadecimalString.hasPrefix("0x") || hexadecimalString.hasPrefix("0X")
            ? unicodeScalars.index(unicodeScalars.startIndex, offsetBy: 2)
            : unicodeScalars.startIndex
        let hexadecimalScalars = unicodeScalars[hexadecimalStartIndex...]
        byteArray.reserveCapacity(hexadecimalScalars.lazy.underestimatedCount)
        
        var byteBuffer: UInt8?
        for unicodeScalar in hexadecimalScalars.lazy {
            guard unicodeScalar.value >= 48 && unicodeScalar.value <= 102 else {
                throw Error.cannotConvertHexadecimalStringToData
            }
            let currentValue: UInt8
            let scalarValue: UInt8 = UInt8(unicodeScalar.value)
            switch scalarValue {
            case let scalarValue where scalarValue <= 57:
                currentValue = scalarValue - 48
            case let scalarValue where scalarValue >= 65 && scalarValue <= 70:
                currentValue = scalarValue - 55
            case let scalarValue where scalarValue >= 97:
                currentValue = scalarValue - 87
            default:
                throw Error.cannotConvertHexadecimalStringToData
            }
            if let bufferedValue = byteBuffer {
                byteArray.append(bufferedValue << 4 | currentValue)
                byteBuffer = nil
            } else {
                byteBuffer = currentValue
            }
        }
        
        guard byteBuffer == nil else { throw Error.cannotConvertHexadecimalStringToData}
        
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
        //var reversedData = Data()
        //for byte in self {
        //    reversedData.insert(byte, at: 0)
        //}
        //return reversedData
    }
}

extension Data {
    func extractValue<T: FixedWidthInteger>(from start: Data.Index) throws -> (value: T, newIndex: Data.Index) {
        let size = MemoryLayout<T>.size
        guard start >= self.startIndex, start + size <= self.endIndex else { throw Error.indexOutOfRange }
        var value: T = 0
        for i in 0..<size {
            value |= T(self[start + i]) << (i * 8)
        }
        let newIndex = start + size
        
        return (T(littleEndian: value), newIndex)
    }
}

extension Array<Data> {
    func generateID() -> Data {
        let totalBytes = reduce(0) { total, input in
            total + input.count
        }
        var hashInput: Data = .init()
        hashInput.reserveCapacity(totalBytes)
        for input in self {
            hashInput.append(input)
        }
        let sha256Hash = OpalCryptoAdapter.sha256(hashInput)
        return sha256Hash
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
