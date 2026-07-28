// OpalBase+Storage+ValueClient.swift

import Foundation

extension _OpalBase.Storage {
    /// Storage backend closures owned and coordinated by `Storage`.
    ///
    /// After passing a value to `Storage`, do not invoke retained copies of its
    /// closures concurrently with Storage APIs. Cross-process or other
    /// out-of-band mutation requires backend-level transactions or
    /// compare-and-swap semantics.
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
            self.valueWriter = { data, key in
                try await valueWriter(Data(data), key)
            }
            self.valueReader = { key in
                try await valueReader(key).map { Data($0) }
            }
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
                values[key.rawValue] = Data(data)
            }
            
            func load(key: OpalBase.Storage.Key) -> Data? {
                values[key.rawValue].map { Data($0) }
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
