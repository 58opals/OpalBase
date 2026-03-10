// OpalBase+Storage+ValueClient.swift

import Foundation

extension _OpalBase.Storage {
    public struct ValueClient: Sendable {
        public var valueWriter: @Sendable (Data, OpalBase.Storage.Key) async throws -> Void
        public var valueReader: @Sendable (OpalBase.Storage.Key) async throws -> Data?
        public var valueDeleter: @Sendable (OpalBase.Storage.Key) async throws -> Void
        public var allValuesDeleter: @Sendable () async throws -> Void
        
        public init(
            valueWriter: @escaping @Sendable (Data, OpalBase.Storage.Key) async throws -> Void,
            valueReader: @escaping @Sendable (OpalBase.Storage.Key) async throws -> Data?,
            valueDeleter: @escaping @Sendable (OpalBase.Storage.Key) async throws -> Void,
            allValuesDeleter: @escaping @Sendable () async throws -> Void
        ) {
            self.valueWriter = valueWriter
            self.valueReader = valueReader
            self.valueDeleter = valueDeleter
            self.allValuesDeleter = allValuesDeleter
        }
    }
}

extension _OpalBase.Storage.ValueClient {
    public static func makeInMemory() -> Self {
        actor Box {
            var values: [String: Data] = .init()
            
            func store(_ data: Data, key: OpalBase.Storage.Key) {
                values[key.rawValue] = data
            }
            
            func load(key: OpalBase.Storage.Key) -> Data? {
                values[key.rawValue]
            }
            
            func remove(key: OpalBase.Storage.Key) {
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
