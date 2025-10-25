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
    func harden() throws -> UInt32 {
        guard self < 0x80000000 else { throw DerivationPath.Error.indexTooLargeForHardening }
        return self | 0x80000000
    }
    
    func unharden() throws -> UInt32 {
        guard self >= 0x80000000 else { throw DerivationPath.Error.indexTooSmallForUnhardening }
        return self & ~0x80000000
    }
}

extension BigUInt {
    func padLeft(to size: Int) -> Data {
        let bytes = self.serialize()
        if bytes.count >= size { return bytes }
        return Data(repeating: 0, count: size - bytes.count) + bytes
    }
}
