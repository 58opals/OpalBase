// Opal Base by 58 Opals

import Foundation

struct ExtendedKeyPair: KeyPair {
    typealias PrivateKeyType = ExtendedPrivateKey
    typealias PublicKeyType = ExtendedPublicKey
    
    let privateKey: PrivateKeyType
    var publicKey: PublicKeyType { privateKey.publicKey }
}
