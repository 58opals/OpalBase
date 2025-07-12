// PublicKey+Error.swift

import Foundation

extension PublicKey {
    enum Error: Swift.Error {
        case invalidFormat
        case invalidLength
        case invalidVersion
        case hardenedDerivation
        case publicKeyDerivationFailed
    }
}
