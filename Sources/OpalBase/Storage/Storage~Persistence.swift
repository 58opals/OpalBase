// Storage~Persistence.swift

import Foundation

extension Storage {
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
    
    func storeValue(_ data: Data, for key: Storage.Key) async throws {
        do {
            try await valueStore.valueWriter(data, key)
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
    
    func loadValue(for key: Storage.Key) async throws -> Data? {
        do {
            return try await valueStore.valueReader(key)
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
    
    func removeValue(for key: Storage.Key) async throws {
        do {
            try await valueStore.valueDeleter(key)
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
    
    func removeAllEntries() async throws {
        do {
            try await valueStore.allValuesDeleter()
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
}
