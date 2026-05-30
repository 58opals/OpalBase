// Array+DataHash.swift

import Foundation

extension Array where Element == Data {
    func generateID() -> Data {
        let totalBytes = reduce(0) { total, input in
            total + input.count
        }
        var hashInput: Data = .init()
        hashInput.reserveCapacity(totalBytes)
        for input in self {
            hashInput.append(input)
        }
        let sha256Hash = OpalCryptoAdapter.sha256(hashInput)
        return sha256Hash
    }
}
