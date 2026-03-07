// OpalBase+PrivateKey+Error.swift

import Foundation

extension _OpalBase.PrivateKey {
    enum Error: Swift.Error {
        case randomBytesGenerationFailed
        case outOfBounds
        case cannotDecodeWIF
        
        case invalidFormat
        case invalidLength
        case invalidVersion
        case invalidChecksum
        case invalidKeyPrefix
        case invalidStringKey
        case invalidDerivedKey
        case derivationPathTooShort
    }
}
