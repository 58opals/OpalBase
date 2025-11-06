// Int+.swift

import Foundation
import BigInt

extension FixedWidthInteger {
    var data: Data {
        var value = self
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    
    var littleEndianData: Data {
        var littleEndian = self.littleEndian
        return Data(bytes: &littleEndian, count: MemoryLayout.size(ofValue: littleEndian))
    }
    
    var bigEndianData: Data {
        var bigEndian = self.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout.size(ofValue: bigEndian))
    }
}

extension UInt32 {
    func hardened() throws -> UInt32 {
        guard self <= Harden.maxUnhardenedValue else { throw DerivationPath.Error.indexTooLargeForHardening }
        return Harden.harden(self)
    }
    
    func unhardened() throws -> UInt32 {
        guard Harden.isHardened(self) else { throw DerivationPath.Error.indexTooSmallForUnhardening }
        return Harden.unharden(self)
    }
}

extension BigUInt {
    func leftPadded(to size: Int) -> Data {
        let bytes = self.serialize()
        if bytes.count >= size { return bytes }
        return Data(repeating: 0, count: size - bytes.count) + bytes
    }
}

enum Harden {
    static let bit: UInt32 = 0x8000_0000
    static let maxUnhardenedValue: UInt32 = bit &- 1
    static func isHardened(_ value: UInt32) -> Bool { (value & bit) != 0 }
    static func harden(_ value: UInt32) -> UInt32 { value | bit }
    static func unharden(_ value: UInt32) -> UInt32 { value & ~bit }
}
