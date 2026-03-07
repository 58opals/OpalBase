// OpalBase+Storage+Error.swift

import Foundation

extension _OpalBase.Storage {
    public enum Error: Swift.Error {
        case persistenceUnavailable
        case persistenceFailure(Swift.Error)
        case encodingFailure(Swift.Error)
        case decodingFailure(Swift.Error)
        case secureStoreFailure(Swift.Error)
        case missingAccountIdentifier(UInt32)
    }
}
