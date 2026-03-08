// OpalBase+Cryptography+NoncePolicy.swift

import Foundation

extension _OpalBase.Cryptography {
    public enum NoncePolicy: Sendable, Equatable {
        case rfc6979BchDefault
        case bipSchnorrDeterministic
        case systemRandom
    }
}

extension _OpalBase.Cryptography.NoncePolicy {
    public enum ECDSA: Sendable, Equatable {
        case rfc6979Sha256
        case systemRandom
    }
}
