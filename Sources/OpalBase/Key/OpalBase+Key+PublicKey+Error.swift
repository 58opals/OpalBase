// OpalBase+Key+PublicKey+Error.swift

import Foundation

extension _OpalBase.Key.PublicKey {
    public enum Error: Swift.Error, Equatable {
        case invalidFormat
        case invalidLength
        case invalidVersion
        case invalidChecksum
        case hardenedDerivation
        case publicKeyDerivationFailed
        case derivationPathTooShort
    }
}
