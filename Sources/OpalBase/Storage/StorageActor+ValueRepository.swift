// StorageActor+ValueRepository.swift

import Foundation

extension StorageActor {
    public struct ValueRepository: Sendable {
        public var valueWriter: @Sendable (Data, StorageActor.KeyModel) async throws -> Void
        public var valueReader: @Sendable (StorageActor.KeyModel) async throws -> Data?
        public var valueDeleter: @Sendable (StorageActor.KeyModel) async throws -> Void
        public var allValuesDeleter: @Sendable () async throws -> Void
        
        public init(
            valueWriter: @escaping @Sendable (Data, StorageActor.KeyModel) async throws -> Void,
            valueReader: @escaping @Sendable (StorageActor.KeyModel) async throws -> Data?,
            valueDeleter: @escaping @Sendable (StorageActor.KeyModel) async throws -> Void,
            allValuesDeleter: @escaping @Sendable () async throws -> Void
        ) {
            self.valueWriter = valueWriter
            self.valueReader = valueReader
            self.valueDeleter = valueDeleter
            self.allValuesDeleter = allValuesDeleter
        }
    }
}

extension StorageActor.ValueRepository {
    public static func makeInMemory() -> Self {
        actor Box {
            var values: [String: Data] = .init()
            
            func store(_ data: Data, key: StorageActor.KeyModel) {
                values[key.rawValue] = data
            }
            
            func load(key: StorageActor.KeyModel) -> Data? {
                values[key.rawValue]
            }
            
            func remove(key: StorageActor.KeyModel) {
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
