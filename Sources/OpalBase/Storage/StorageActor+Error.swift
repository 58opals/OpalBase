// StorageActor.swift

import Foundation

public actor StorageActor {
    let security: SecurityModel
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let valueStore: ValueRepository
    
    public init(
        valueStore: ValueRepository = .makeInMemory(),
        security: SecurityModel = .makePlaintextOnly()
    ) throws {
        self.valueStore = valueStore
        self.security = security
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }
}

extension StorageActor {
    public enum Error: Swift.Error {
        case persistenceUnavailable
        case persistenceFailure(Swift.Error)
        case encodingFailure(Swift.Error)
        case decodingFailure(Swift.Error)
        case secureStoreFailure(Swift.Error)
        case missingAccountIdentifier(UInt32)
    }
}
