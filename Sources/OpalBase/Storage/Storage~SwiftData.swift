// Storage~SwiftData.swift

import Foundation
import SwiftData

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
    
    func storeValue(_ data: Data, for key: Storage.Key) throws {
        let entry: Storage.Value
        if let existingEntry = try fetchEntry(for: key) {
            entry = existingEntry
        } else {
            entry = Storage.Value(key: key.rawValue, payload: data, updatedAt: Date())
            modelContext.insert(entry)
        }
        
        if entry.payload != data {
            entry.payload = data
        }
        entry.updatedAt = Date()
        
        do {
            try modelContext.save()
        } catch {
            throw Error.swiftDataFailure(error)
        }
    }
    
    func loadValue(for key: Storage.Key) throws -> Data? {
        try fetchEntry(for: key)?.payload
    }
    
    func removeValue(for key: Storage.Key) throws {
        guard let entry = try fetchEntry(for: key) else { return }
        modelContext.delete(entry)
        do {
            try modelContext.save()
        } catch {
            throw Error.swiftDataFailure(error)
        }
    }
    
    func removeAllEntries() throws {
        let descriptor = FetchDescriptor<Storage.Value>()
        let entries: [Storage.Value]
        do {
            entries = try modelContext.fetch(descriptor)
        } catch {
            throw Error.swiftDataFailure(error)
        }
        
        for entry in entries {
            modelContext.delete(entry)
        }
        
        do {
            try modelContext.save()
        } catch {
            throw Error.swiftDataFailure(error)
        }
    }
    
    func fetchEntry(for key: Storage.Key) throws -> Storage.Value? {
        let predicate = #Predicate<Storage.Value> { $0.key == key.rawValue }
        var descriptor = FetchDescriptor<Storage.Value>(predicate: predicate)
        descriptor.fetchLimit = 1
        
        let entries: [Storage.Value]
        do {
            entries = try modelContext.fetch(descriptor)
        } catch {
            throw Error.swiftDataFailure(error)
        }
        return entries.first
    }
}
