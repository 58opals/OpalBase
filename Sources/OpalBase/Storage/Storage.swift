// Storage.swift

import Foundation

public actor Storage {
    let security: Security
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let valueStore: ValueStore
    
    public init(
        valueStore: ValueStore = .makeInMemory(),
        securityOptions: Security.Options = .init()
    ) throws {
        self.valueStore = valueStore
        self.security = Security(options: securityOptions)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }
}

extension Storage {
    public enum Error: Swift.Error {
        case persistenceUnavailable
        case persistenceFailure(Swift.Error)
        case encodingFailure(Swift.Error)
        case decodingFailure(Swift.Error)
        case secureStoreFailure(Swift.Error)
        case missingAccountIdentifier(UInt32)
    }
}
