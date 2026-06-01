// OpalBase+Storage+Persistence.swift

import Foundation

extension _OpalBase.Storage {
    func encodeSnapshot<Value: Codable>(_ value: Value) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw Error.encodingFailure(error)
        }
    }
    
    func decodeSnapshot<Value: Codable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw Error.decodingFailure(error)
        }
    }
    
    func storeValue(_ data: Data, for key: OpalBase.Storage.Key) async throws {
        try await mapPersistenceError {
            try await valueClient.valueWriter(data, key)
        }
    }
    
    func loadValue(for key: OpalBase.Storage.Key) async throws -> Data? {
        try await mapPersistenceError {
            try await valueClient.valueReader(key)
        }
    }
    
    func removeValue(for key: OpalBase.Storage.Key) async throws {
        try await mapPersistenceError {
            try await valueClient.valueDeleter(key)
        }
    }
    
    func removeAllEntries() async throws {
        try await mapPersistenceError {
            try await valueClient.allValuesDeleter()
        }
    }
}

private extension _OpalBase.Storage {
    func mapPersistenceError<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
}
