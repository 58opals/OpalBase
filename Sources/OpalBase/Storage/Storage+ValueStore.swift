// Storage+ValueStore.swift

import Foundation

extension Storage {
    public struct ValueStore: Sendable {
        public var storeValue: @Sendable (Data, Storage.Key) async throws -> Void
        public var loadValue: @Sendable (Storage.Key) async throws -> Data?
        public var removeValue: @Sendable (Storage.Key) async throws -> Void
        public var removeAllValues: @Sendable () async throws -> Void

        public init(
            storeValue: @escaping @Sendable (Data, Storage.Key) async throws -> Void,
            loadValue: @escaping @Sendable (Storage.Key) async throws -> Data?,
            removeValue: @escaping @Sendable (Storage.Key) async throws -> Void,
            removeAllValues: @escaping @Sendable () async throws -> Void
        ) {
            self.storeValue = storeValue
            self.loadValue = loadValue
            self.removeValue = removeValue
            self.removeAllValues = removeAllValues
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
        return .init(storeValue: { data, key in
            await box.store(data, key: key)
        },
        loadValue: { key in
            await box.load(key: key)
        },
        removeValue: { key in
            await box.remove(key: key)
        },
        removeAllValues: {
            await box.removeAll()
        })
    }
}
