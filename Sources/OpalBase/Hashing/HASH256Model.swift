// HASH256Model.swift

import Foundation

struct HASH256Model {
    static func hash(_ data: Data) -> Data {
        let firstHash = SHA256Model.hash(data)
        let secondHash = SHA256Model.hash(firstHash)
        return secondHash
    }
    
    static func computeChecksum(for data: Data) -> Data {
        let hash256 = HASH256Model.hash(data)
        let checksum = hash256[0..<4]
        return checksum
    }
}
