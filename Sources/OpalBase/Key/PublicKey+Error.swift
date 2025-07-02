// PublicKey+Error.swift

import Foundation

extension PublicKey {
    public enum Error: Swift.Error {
        case invalidLength
        case publicKeyDerivationFailed
    }
}
