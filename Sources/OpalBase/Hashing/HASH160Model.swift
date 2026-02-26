// HASH160Model.swift

import Foundation

struct HASH160Model {
    static func hash(_ data: Data) -> Data {
        let sha256 = SHA256Model.hash(data)
        let ripemd160 = RIPEMD160Model.hash(sha256)
        return ripemd160
    }
}
