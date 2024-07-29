import Foundation

enum CompactSize {
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    
    /// Initializes a CompactSize instance from a UInt64 value.
    /// - Parameter value: The UInt64 value to initialize from.
    init(value: UInt64) {
        switch value {
        case 0...0xFC:
            self = .uint8(UInt8(value))
        case 0xFD...0xFFFF:
            self = .uint16(UInt16(value))
        case 0x10000...0xFFFFFFFF:
            self = .uint32(UInt32(value))
        default:
            self = .uint64(value)
        }
    }
    
    /// Initializes a CompactSize instance from Data.
    /// - Parameter data: The data to initialize from.
    /// - Throws: `CompactSize.Error` if the data is insufficient or the prefix is invalid.
    init(data: Data) throws {
        guard let prefix = data.first else {
            throw Error.insufficientData
        }
        
        switch prefix {
        case 0x00...0xFC:
            self = .uint8(prefix)
        case 0xFD:
            guard data.count >= 3 else { throw Error.insufficientData }
            let (value, _): (UInt16, Data.Index) = data.extractValue(from: 1)
            self = .uint16(value)
        case 0xFE:
            guard data.count >= 5 else { throw Error.insufficientData }
            let (value, _): (UInt32, Data.Index) = data.extractValue(from: 1)
            self = .uint32(value)
        case 0xFF:
            guard data.count >= 9 else { throw Error.insufficientData }
            let (value, _): (UInt64, Data.Index) = data.extractValue(from: 1)
            self = .uint64(value)
        default:
            throw Error.invalidPrefix
        }
    }
    
    /// Encodes the CompactSize value into Data.
    /// - Returns: The encoded data.
    func encode() -> Data {
        var data = Data()
        switch self {
        case .uint8(let value):
            data.append(value)
        case .uint16(let value):
            data.append(0xFD)
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        case .uint32(let value):
            data.append(0xFE)
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        case .uint64(let value):
            data.append(0xFF)
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        }
        return data
    }
    
    /// Decodes a CompactSize instance from Data.
    /// - Parameter data: The data to decode from.
    /// - Throws: `CompactSize.Error` if decoding fails.
    /// - Returns: A tuple containing the decoded CompactSize and the number of bytes read.
    static func decode(from data: Data) throws -> (CompactSize, Int) {
        let compactSize = try CompactSize(data: data)
        let bytesRead: Int
        
        switch compactSize {
        case .uint8:
            bytesRead = 1
        case .uint16:
            bytesRead = 3
        case .uint32:
            bytesRead = 5
        case .uint64:
            bytesRead = 9
        }
        
        return (compactSize, bytesRead)
    }
    
    /// Returns the UInt64 representation of the CompactSize.
    var value: UInt64 {
        switch self {
        case .uint8(let value): return UInt64(value)
        case .uint16(let value): return UInt64(value)
        case .uint32(let value): return UInt64(value)
        case .uint64(let value): return value
        }
    }
}
