// HASH160.swift

import Foundation

struct HASH160 {
    static func hash(_ data: Data) -> Data {
        let sha256 = SHA256.hash(data)
        let ripemd160 = RIPEMD160.hash(sha256)
        return ripemd160
    }
}
