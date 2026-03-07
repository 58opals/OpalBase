// NonceFunctionModel+ECDSA.swift

import Foundation

public enum NonceFunctionModel: Sendable, Equatable {
    case rfc6979BchDefault
    case bipSchnorrDeterministic
    case systemRandom
}

extension NonceFunctionModel {
    public enum ECDSA: Sendable, Equatable {
        case rfc6979Sha256
        case systemRandom
    }
}

