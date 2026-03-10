// OpalBase+PublicKey+Error.swift

import Foundation

extension _OpalBase.PublicKey {
    enum Error: Swift.Error {
        case invalidFormat
        case invalidLength
        case invalidVersion
        case invalidChecksum
        case hardenedDerivation
        case publicKeyDerivationFailed
        case derivationPathTooShort
    }
}
