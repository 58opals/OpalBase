import Foundation

extension Data {
    init(hexString: String) throws {
        var byteArray = [UInt8]()
        byteArray.reserveCapacity(hexString.unicodeScalars.lazy.underestimatedCount)
        
        var byteBuffer: UInt8?
        var charactersToSkip = hexString.hasPrefix("0x") ? 2 : 0
        for unicodeScalar in hexString.unicodeScalars.lazy {
            guard charactersToSkip == 0 else {
                charactersToSkip -= 1
                continue
            }
            guard unicodeScalar.value >= 48 && unicodeScalar.value <= 102 else {
                throw Error.cannotConvertHexStringToData
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
                throw Error.cannotConvertHexStringToData
            }
            if let bufferedValue = byteBuffer {
                byteArray.append(bufferedValue << 4 | currentValue)
                byteBuffer = nil
            } else {
                byteBuffer = currentValue
            }
        }
        if let bufferedValue = byteBuffer {
            byteArray.append(bufferedValue)
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
        var reversedData = Data()
        for byte in self {
            reversedData.insert(byte, at: 0)
        }
        return reversedData
    }
}

extension Data {
    func extractValue<T: FixedWidthInteger>(from start: Data.Index) -> (value: T, newIndex: Data.Index) {
        let size = MemoryLayout<T>.size
        guard start + size <= self.endIndex else { fatalError("Index out of range") }
        var value: T = 0
        for i in 0..<size {
            value |= T(self[start + i]) << (i * 8)
        }
        let newIndex = start + size
        
        return (T(littleEndian: value), newIndex)
    }
}

