// Opal Base by 58 Opals

import Foundation

protocol PrivateKey: Key {
    associatedtype PublicKeyType: PublicKey
    
    var network: BitcoinCash.Network { get }
    var data: Data { get }
    var publicKey: PublicKeyType { get }
    
    func createSignature(for message: Data) -> Data
}

extension PrivateKey {
    var description: String {
        """
        ** Private Key **
            raw:   \(data.hexadecimal)
        """
    }
}
