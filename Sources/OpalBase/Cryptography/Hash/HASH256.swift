// HASH256.swift

import Foundation

struct HASH256 {
    static func hash(_ data: Data) -> Data {
        let firstHash = SHA256.hash(data)
        let secondHash = SHA256.hash(firstHash)
        return secondHash
    }
    
    static func getChecksum(_ data: Data) -> Data {
        let hash256 = HASH256.hash(data)
        let checksum = hash256[0..<4]
        return checksum
    }
}
