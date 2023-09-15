// Opal Base by 58 Opals

import Foundation

struct BasicPrivateKey: PrivateKey, CustomStringConvertible {
    typealias PublicKeyType = BasicPublicKey
    
    let algorithm: Cryptography.Algorithm
    let network: BitcoinCash.Network
    let data: Data
    
    init(_ data: Data = Data.generateSecuredRandomBytes(count: 32),
         using algorithm: Cryptography.Algorithm,
         on network: BitcoinCash.Network = .mainnet) {
        self.data = data
        self.algorithm = algorithm
        self.network = network
    }
    
    var publicKey: PublicKeyType {
        return Cryptography.k1.generatePublicKey(from: self)
    }
    
    func createSignature(for message: Data) -> Data {
        return Cryptography.k1.sign(message: message, from: self)
    }
}
