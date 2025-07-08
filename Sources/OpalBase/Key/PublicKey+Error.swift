// PublicKey+Error.swift

import Foundation

extension PublicKey {
    public enum Error: Swift.Error {
        case invalidFormat
        case invalidLength
        case invalidVersion
        case hardenedDerivation
        case publicKeyDerivationFailed
    }
}
