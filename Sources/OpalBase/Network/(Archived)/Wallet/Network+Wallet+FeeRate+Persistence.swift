// Network+Wallet+FeeRate+Persistence.swift

import Foundation

extension Network.Wallet.FeeRate {
    public struct Persistence: Sendable {
        public struct Snapshot: Sendable, Equatable {
            public let tier: Tier
            public let value: UInt64
            public let timestamp: Date
            public let version: UInt64
            
            public init(tier: Tier, value: UInt64, timestamp: Date, version: UInt64) {
                self.tier = tier
                self.value = value
                self.timestamp = timestamp
                self.version = version
            }
        }
        
        public enum Error: Swift.Error, Sendable, Equatable {
            case conflict(expected: UInt64?, actual: UInt64?)
            case repository(String)
        }
        
        public typealias Loader = @Sendable (Tier, TimeInterval) async throws -> Snapshot?
        public typealias Writer = @Sendable (Tier, UInt64, TimeInterval, UInt64?) async throws -> Snapshot
        public typealias Remover = @Sendable (Tier, UInt64?) async throws -> Void
        
        private let loader: Loader
        private let writer: Writer
        private let remover: Remover
        
        public init(loader: @escaping Loader,
                    writer: @escaping Writer,
                    remover: @escaping Remover) {
            self.loader = loader
            self.writer = writer
            self.remover = remover
        }
        
        func load(tier: Tier, maxAge: TimeInterval) async throws -> Snapshot? {
            try await loader(tier, maxAge)
        }
        
        func store(tier: Tier,
                   value: UInt64,
                   ttl: TimeInterval,
                   expectedVersion: UInt64?) async throws -> Snapshot {
            try await writer(tier, value, ttl, expectedVersion)
        }
        
        func invalidate(tier: Tier, expectedVersion: UInt64?) async throws {
            try await remover(tier, expectedVersion)
        }
        
        static var noop: Persistence {
            Persistence(
                loader: { _, _ in
                    nil
                },
                writer: { tier, value, _, expected in
                        .init(tier: tier,
                              value: value,
                              timestamp: .now,
                              version: expected ?? 0)
                },
                remover: { _, _ in
                })
        }
    }
}

#if canImport(SwiftData)
extension Network.Wallet.FeeRate.Persistence {
    static func storage(repository: Storage.Repository.Fees) -> Self {
        Self(
            loader: { tier, maxAge in
                guard let row = try await repository.latest(tier.storageTier, maxAge: maxAge) else {
                    return nil
                }
                return .init(tier: tier,
                             value: row.satsPerByte,
                             timestamp: row.timestamp,
                             version: row.version)
            },
            writer: { tier, value, ttl, expected in
                do {
                    let row = try await repository.put(tier: tier.storageTier,
                                                       satsPerByte: value,
                                                       ttl: ttl,
                                                       expectedVersion: expected)
                    return .init(tier: tier,
                                 value: row.satsPerByte,
                                 timestamp: row.timestamp,
                                 version: row.version)
                } catch let error as Storage.Repository.Fees.Error {
                    switch error {
                    case let .conflict(expected, actual):
                        throw Error.conflict(expected: expected, actual: actual)
                    case let .storage(description):
                        throw Error.repository(description)
                    }
                }
            },
            remover: { tier, expected in
                do {
                    try await repository.remove(tier.storageTier, expectedVersion: expected)
                } catch let error as Storage.Repository.Fees.Error {
                    switch error {
                    case let .storage(description):
                        throw Error.repository(description)
                    case let .conflict(expected, actual):
                        throw Error.conflict(expected: expected, actual: actual)
                    }
                }
            })
    }
}
#endif
