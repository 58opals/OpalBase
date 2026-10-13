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
            self.encoder.dateEncodingStrategy = .deferredToDate
            self.decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                if let legacyTimestamp = try? container.decode(String.self) {
                    guard let date = try? Date.ISO8601FormatStyle().parse(legacyTimestamp) else {
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "Invalid ISO-8601 timestamp"
                        )
                    }
                    return date
                }
                return try Date(from: decoder)
            }
        }
    }
}
