// Opal Base by 58 Opals

import Foundation
import BigInt

import Foundation

protocol PublicKey: Key {
    var uncompressed: Data { get }
    var compressed: Data { get }
    var der: Data { get }
    var pem: String { get }
    var x963: Data { get }
    var hash160: Data { get }
    
    func validate(signature: Data, for message: Data) -> Bool
}

extension PublicKey {
    var description: String {
        """
        ** Public Key **
            uncompressed:   \(uncompressed.hexadecimal)
            compressed:     \(compressed.hexadecimal)
            hash160:        \(hash160.hexadecimal)
            address:        \(LegacyAddress(publicKey: self, representation: .p2pkh))
        """
    }
}
