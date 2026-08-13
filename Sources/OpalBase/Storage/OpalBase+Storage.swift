// OpalBase+Storage.swift

import Foundation

extension OpalBase {
    public actor Storage {
        let security: Security
        let encoder: JSONEncoder
        let decoder: JSONDecoder
        let valueClient: ValueClient
        let secretPersistencePolicy: Security.PersistencePolicy

        /// Creates one storage root with an immutable policy for all mnemonic writes.
        public init(
            valueClient: ValueClient,
            security: Security,
            secretPersistencePolicy: Security.PersistencePolicy
        ) throws {
            self.valueClient = valueClient
            self.security = security
            self.secretPersistencePolicy = secretPersistencePolicy
            self.encoder = JSONEncoder()
            self.decoder = JSONDecoder()
            self.encoder.dateEncodingStrategy = .iso8601
            self.decoder.dateDecodingStrategy = .iso8601
        }
    }
}
