// Opal Base by 58 Opals

import Foundation

struct PolyMod {
    static let polynomial1: UInt = 0x98f2bc8e61
    static let polynomial2: UInt = 0x79b76d99e2
    static let polynomial3: UInt = 0xf33e5fb3c4
    static let polynomial4: UInt = 0xae2eabe2a8
    static let polynomial5: UInt = 0x1e4f43e470
    static let finalChecksumXOR: UInt = 1
    
    static func encode(_ bytes: Data) -> UInt {
        var checksumValue: UInt = 1
        for byte in bytes {
            let highBits: UInt8 = UInt8(checksumValue >> 35)
            checksumValue = ((checksumValue & 0x07ffffffff) << 5) ^ UInt(byte)
            if highBits & 0x01 != 0 { checksumValue ^= polynomial1 }
            if highBits & 0x02 != 0 { checksumValue ^= polynomial2 }
            if highBits & 0x04 != 0 { checksumValue ^= polynomial3 }
            if highBits & 0x08 != 0 { checksumValue ^= polynomial4 }
            if highBits & 0x10 != 0 { checksumValue ^= polynomial5 }
        }
        
        return checksumValue ^ finalChecksumXOR
    }
}
