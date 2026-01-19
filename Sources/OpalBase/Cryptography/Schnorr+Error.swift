// Schnorr+Error.swift

import Foundation

public extension Schnorr {
    enum Error: Swift.Error, Equatable {
        case invalidDigestLength(actual: Int)
        case invalidPrivateKeyLength(actual: Int)
        case invalidPrivateKeyValue
        case invalidPublicKeyLength(actual: Int)
        case invalidSignatureLength(actual: Int)
        case randomGenerationFailed(status: Int32)
    }
}
