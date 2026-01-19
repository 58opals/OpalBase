// NonceFunction.swift

import Foundation

public enum NonceFunction: Sendable, Equatable {
    case rfc6979BchDefault
    case bipSchnorrDeterministic
    case systemRandom
}

extension NonceFunction {
    public enum ECDSA: Sendable, Equatable {
        case rfc6979Sha256
        case systemRandom
    }
}
