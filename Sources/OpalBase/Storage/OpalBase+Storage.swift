// OpalBase+Storage.swift

import Foundation

extension OpalBase {
    public actor Storage {
        let security: Security
        let encoder: JSONEncoder
        let decoder: JSONDecoder
        let valueClient: ValueClient
        
        public init(
            valueClient: ValueClient = .makeInMemory(),
            security: Security = .makePlaintextOnly()
        ) throws {
            self.valueClient = valueClient
            self.security = security
            self.encoder = JSONEncoder()
            self.decoder = JSONDecoder()
            self.encoder.dateEncodingStrategy = .iso8601
            self.decoder.dateDecodingStrategy = .iso8601
        }
    }
}
