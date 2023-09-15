// Opal Base by 58 Opals

import Foundation
import CryptoKit

extension SHA256 {
    static func doubleHash<D>(data: D) -> SHA256Digest where D: DataProtocol {
        let firstHash = SHA256.hash(data: data)
        let secondHash = SHA256.hash(data: Data(firstHash))
        return secondHash
    }
    
    static func getChecksumForBitcoin(of rawData: Data,
                                      numberOfRound: Int = 2,
                                      numberOfBytes: Int = 4) -> Data {
        var data = rawData
        (1...numberOfRound).forEach { _ in
            data = Data(SHA256.hash(data: data))
        }
        
        return data[0..<numberOfBytes]
    }
}
