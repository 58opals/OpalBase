// Opal Base by 58 Opals

import Foundation

protocol KeyPair {
    associatedtype PrivateKeyType: PrivateKey
    associatedtype PublicKeyType: PublicKey
    
    var privateKey: PrivateKeyType { get }
    var publicKey: PublicKeyType { get }
}
