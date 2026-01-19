// Secp256k1+Error.swift

import Foundation

public extension Secp256k1 {
    enum Error: Swift.Error, Equatable {
        case invalidDigestLength(actual: Int)
        case invalidPrivateKeyLength(actual: Int)
        case invalidPrivateKeyValue
        case invalidPublicKeyLength(actual: Int)
        case invalidSignatureLength(actual: Int)
        
        case invalidSignatureScalar
        case signatureComponentZero
        case derMalformed
        case derNonCanonical
        case randomGenerationFailed(status: Int32)
    }
}
