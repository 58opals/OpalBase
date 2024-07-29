import Foundation

struct Polymod {
    static func compute(_ values: [UInt8]) -> UInt64 {
         var checksum: UInt64 = 1
         for value in values {
             let topBits = checksum >> 35
             checksum = ((checksum & 0x07ffffffff) << 5) ^ UInt64(value)
             if topBits & 0x01 != 0 { checksum ^= 0x98f2bc8e61 }
             if topBits & 0x02 != 0 { checksum ^= 0x79b76d99e2 }
             if topBits & 0x04 != 0 { checksum ^= 0xf33e5fb3c4 }
             if topBits & 0x08 != 0 { checksum ^= 0xae2eabe2a8 }
             if topBits & 0x10 != 0 { checksum ^= 0x1e4f43e470 }
         }
        return (checksum ^ 1)
     }
}
