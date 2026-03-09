// Data+Writer.swift

import Foundation

extension Data {
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
