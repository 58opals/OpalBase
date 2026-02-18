// Storage~Persistence.swift

import Foundation

extension Storage {
    @MainActor
    func encodeSnapshot<Value: Codable>(_ value: Value) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw Error.encodingFailure(error)
        }
    }
    
    @MainActor
    func decodeSnapshot<Value: Codable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw Error.decodingFailure(error)
        }
    }
    
    func storeValue(_ data: Data, for key: Storage.Key) async throws {
        try await mapPersistenceError {
            try await valueStore.valueWriter(data, key)
        }
    }
    
    func loadValue(for key: Storage.Key) async throws -> Data? {
        try await mapPersistenceError {
            try await valueStore.valueReader(key)
        }
    }
    
    func removeValue(for key: Storage.Key) async throws {
        try await mapPersistenceError {
            try await valueStore.valueDeleter(key)
        }
    }
    
    func removeAllEntries() async throws {
        try await mapPersistenceError {
            try await valueStore.allValuesDeleter()
        }
    }
}

private extension Storage {
    func mapPersistenceError<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
}
