// Opal Base by 58 Opals

import Foundation

struct PolyMod {
    func encode(_ bytes: Data) -> UInt {
        var c: UInt = 1
        for byte in bytes {
            let c0: UInt8 = UInt8(c >> 35)
            c = ((c & 0x07ffffffff) << 5) ^ UInt(byte)
            if c0 & 0x01 != 0 { c ^= 0x98f2bc8e61 }
            if c0 & 0x02 != 0 { c ^= 0x79b76d99e2 }
            if c0 & 0x04 != 0 { c ^= 0xf33e5fb3c4 }
            if c0 & 0x08 != 0 { c ^= 0xae2eabe2a8 }
            if c0 & 0x10 != 0 { c ^= 0x1e4f43e470 }
        }
        
        return c ^ 1
    }
}
