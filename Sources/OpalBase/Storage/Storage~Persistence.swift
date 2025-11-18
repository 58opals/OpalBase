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
            try await valueStore.storeValue(data, key)
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
    
    func loadValue(for key: Storage.Key) async throws -> Data? {
        do {
            return try await valueStore.loadValue(key)
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
    
    func removeValue(for key: Storage.Key) async throws {
        do {
            try await valueStore.removeValue(key)
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
    
    func removeAllEntries() async throws {
        do {
            try await valueStore.removeAllValues()
        } catch {
            throw Error.persistenceFailure(error)
        }
    }
}
