// Opal Base by 58 Opals

import Foundation

struct BasicPublicKey: PublicKey, CustomStringConvertible {
    let algorithm: Cryptography.Algorithm
    let network: BitcoinCash.Network
    
    let uncompressed: Data
    let compressed: Data
    let der: Data
    let pem: String
    let x963: Data
    let hash160: Data
    
    func validate(signature: Data, for message: Data) -> Bool {
        let doubleHashedMessage = Cryptography.sha256.doubleHash(data: message)
        return Cryptography.k1.validate(signature: signature, for: doubleHashedMessage, from: self)
    }
}
