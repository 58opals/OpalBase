// Secp256k1+Constant.swift

import Foundation

extension Secp256k1 {
    enum Constant {
        static let p = UInt256(
            limbs: [
                0xfffffffefffffc2f,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0xffffffffffffffff
            ]
        )
        
        static let n = UInt256(
            limbs: [
                0xbfd25e8cd0364141,
                0xbaaedce6af48a03b,
                0xfffffffffffffffe,
                0xffffffffffffffff
            ]
        )
        
        static let Gx = UInt256(
            limbs: [
                0x59f2815b16f81798,
                0x029bfcdb2dce28d9,
                0x55a06295ce870b07,
                0x79be667ef9dcbbac
            ]
        )
        
        static let Gy = UInt256(
            limbs: [
                0x9c47d08ffb10d4b8,
                0xfd17b448a6855419,
                0x5da4fbfc0e1108a8,
                0x483ada7726a3c465
            ]
        )
    }
}
