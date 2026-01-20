// Secp256k1+Constant.swift

import Foundation

extension Secp256k1 {
    enum Constant {
        @usableFromInline static let p = UInt256(
            limbs: [
                0xfffffffefffffc2f,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0xffffffffffffffff
            ]
        )
        
        @usableFromInline static let n = UInt256(
            limbs: [
                0xbfd25e8cd0364141,
                0xbaaedce6af48a03b,
                0xfffffffffffffffe,
                0xffffffffffffffff
            ]
        )
        
        @usableFromInline static let Gx = UInt256(
            limbs: [
                0x59f2815b16f81798,
                0x029bfcdb2dce28d9,
                0x55a06295ce870b07,
                0x79be667ef9dcbbac
            ]
        )
        
        @usableFromInline static let Gy = UInt256(
            limbs: [
                0x9c47d08ffb10d4b8,
                0xfd17b448a6855419,
                0x5da4fbfc0e1108a8,
                0x483ada7726a3c465
            ]
        )
        
        @usableFromInline static let endomorphismBeta = UInt256(
            limbs: [
                0xc1396c28719501ee,
                0x9cf0497512f58995,
                0x6e64479eac3434e9,
                0x7ae96a2b657c0710
            ]
        )
        
        @usableFromInline static let endomorphismLambda = UInt256(
            limbs: [
                0xdf02967c1b23bd72,
                0x122e22ea20816678,
                0xa5261c028812645a,
                0x5363ad4cc05c30e0
            ]
        )
        
        @usableFromInline static let endomorphismCoefficientOne = UInt256(
            limbs: [
                0xe893209a45dbb031,
                0x3daa8a1471e8ca7f,
                0xe86c90e49284eb15,
                0x3086d221a7d46bcd
            ]
        )
        
        @usableFromInline static let endomorphismCoefficientTwo = UInt256(
            limbs: [
                0x1571b4ae8ac47f71,
                0x221208ac9df506c6,
                0x6f547fa90abfe4c4,
                0xe4437ed6010e8828
            ]
        )
        
        @usableFromInline static let endomorphismMinusBasisOne = UInt256(
            limbs: [
                0x6f547fa90abfe4c3,
                0xe4437ed6010e8828,
                0x0000000000000000,
                0x0000000000000000
            ]
        )
        
        @usableFromInline static let endomorphismMinusBasisTwo = UInt256(
            limbs: [
                0xd765cda83db1562c,
                0x8a280ac50774346d,
                0xfffffffffffffffe,
                0xffffffffffffffff
            ]
        )
    }
}
