// Opal Base by 58 Opals

import Foundation

struct BasicKeyPair: KeyPair {
    typealias PrivateKeyType = BasicPrivateKey
    typealias PublicKeyType = BasicPublicKey
    
    let privateKey: BasicPrivateKey
    var publicKey: BasicPublicKey { privateKey.publicKey }
}

