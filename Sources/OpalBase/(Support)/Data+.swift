// Data+.swift

import Foundation

extension Data {
    enum Error: Swift.Error {
        case cannotConvertHexadecimalStringToData
        case indexOutOfRange
    }
}

extension Data {
    public init(hexadecimalString: String) throws {
        var byteArray = [UInt8]()
        byteArray.reserveCapacity(hexadecimalString.unicodeScalars.lazy.underestimatedCount)
        
        var byteBuffer: UInt8?
        var charactersToSkip = hexadecimalString.hasPrefix("0x") ? 2 : 0
        for unicodeScalar in hexadecimalString.unicodeScalars.lazy {
            guard charactersToSkip == 0 else {
                charactersToSkip -= 1
                continue
            }
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
        guard start + size <= self.endIndex else { throw Error.indexOutOfRange }
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
        let sha256Hash = SHA256.hash(hashInput)
        return sha256Hash
    }
}

extension Data {
    static func push(_ buffer: Data) -> Data {
        switch buffer.count {
        case 0...75:
            return Data([UInt8(buffer.count)]) + buffer
        case 76...255:
            return Data([OP._PUSHDATA1.rawValue, UInt8(buffer.count)]) + buffer
        case 256...65535:
            return Data([OP._PUSHDATA2.rawValue]) + UInt16(buffer.count).littleEndianData + buffer
        default:
            return Data([OP._PUSHDATA4.rawValue]) + UInt32(buffer.count).littleEndianData + buffer
        }
    }
}
