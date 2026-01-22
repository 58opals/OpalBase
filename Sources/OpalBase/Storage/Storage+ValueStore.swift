// Storage+ValueStore.swift

import Foundation

extension Storage {
    public struct ValueStore: Sendable {
        public var valueWriter: @Sendable (Data, Storage.Key) async throws -> Void
        public var valueReader: @Sendable (Storage.Key) async throws -> Data?
        public var valueDeleter: @Sendable (Storage.Key) async throws -> Void
        public var allValuesDeleter: @Sendable () async throws -> Void
        
        public init(
            valueWriter: @escaping @Sendable (Data, Storage.Key) async throws -> Void,
            valueReader: @escaping @Sendable (Storage.Key) async throws -> Data?,
            valueDeleter: @escaping @Sendable (Storage.Key) async throws -> Void,
            allValuesDeleter: @escaping @Sendable () async throws -> Void
        ) {
            self.valueWriter = valueWriter
            self.valueReader = valueReader
            self.valueDeleter = valueDeleter
            self.allValuesDeleter = allValuesDeleter
        }
    }
}

extension Storage.ValueStore {
    public static func makeInMemory() -> Self {
        actor Box {
            var values: [String: Data] = .init()
            
            func store(_ data: Data, key: Storage.Key) {
                values[key.rawValue] = data
            }
            
            func load(key: Storage.Key) -> Data? {
                values[key.rawValue]
            }
            
            func remove(key: Storage.Key) {
                values.removeValue(forKey: key.rawValue)
            }
            
            func removeAll() {
                values.removeAll()
            }
        }
        
        let box = Box()
        return .init(valueWriter: { data, key in
            await box.store(data, key: key)
        },
                     valueReader: { key in
            await box.load(key: key)
        },
                     valueDeleter: { key in
            await box.remove(key: key)
        },
                     allValuesDeleter: {
            await box.removeAll()
        })
    }
}
