// OpalBase+Storage.swift

import Foundation

extension OpalBase {
    public actor Storage {
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
}
