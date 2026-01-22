// Data+BinaryInputOutput.swift

import Foundation

extension Data {
    struct Reader {
        let data: Data
        private let startIndex: Data.Index
        private(set) var index: Data.Index
        
        init(_ data: Data, startingAt index: Data.Index? = nil) {
            self.data = data
            self.startIndex = index ?? data.startIndex
            self.index = self.startIndex
        }
        
        var bytesRead: Int {
            data.distance(from: startIndex, to: index)
        }
        
        var remainingData: Data {
            data[index...]
        }
        
        mutating func readLittleEndian<T: FixedWidthInteger>(_ type: T.Type = T.self) throws -> T {
            let (value, nextIndex): (T, Data.Index) = try data.extractValue(from: index)
            index = nextIndex
            return value
        }
        
        mutating func readData(count: Int) throws -> Data {
            guard let nextIndex = data.index(index, offsetBy: count, limitedBy: data.endIndex) else {
                throw Data.Error.indexOutOfRange
            }
            let slice = data[index..<nextIndex]
            index = nextIndex
            return Data(slice)
        }
        
        mutating func readCompactSize() throws -> CompactSize {
            let (value, size) = try CompactSize.decode(from: data[index...])
            index += size
            return value
        }
        
        mutating func advance(by count: Int) throws {
            guard count >= 0 else { throw Error.negativeAdvance(count) }
            guard let nextIndex = data.index(index, offsetBy: count, limitedBy: data.endIndex) else {
                throw Error.endOfData
            }
            index = nextIndex
        }
        
        enum Error: Swift.Error {
            case endOfData
            case negativeAdvance(Int)
        }
    }
    
    struct Writer {
        private(set) var data: Data = .init()
        
        mutating func reserveCapacity(_ capacity: Int) {
            data.reserveCapacity(capacity)
        }
        
        mutating func writeByte(_ byte: UInt8) {
            data.append(byte)
        }
        
        mutating func writeLittleEndian<T: FixedWidthInteger>(_ value: T) {
            var littleEndianValue = value.littleEndian
            Swift.withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
        }
        
        mutating func writeData(_ bytes: Data) {
            data.append(bytes)
        }
        
        mutating func writeCompactSize(_ value: CompactSize) {
            switch value.value {
            case 0...252:
                writeByte(UInt8(value.value))
            case 253...0xffff:
                writeByte(253)
                writeLittleEndian(UInt16(value.value))
            case 0x1_0000...0xffff_ffff:
                writeByte(254)
                writeLittleEndian(UInt32(value.value))
            default:
                writeByte(255)
                writeLittleEndian(UInt64(value.value))
            }
        }
    }
}
