// Network+Wallet+FeeRate+Persistence.swift

import Foundation

extension Network.Wallet.FeeRate {
    public struct Persistence: Sendable {
        public typealias Loader = @Sendable (Tier, TimeInterval) async throws -> UInt64?
        public typealias Writer = @Sendable (Tier, UInt64, TimeInterval) async throws -> Void

        private let loader: Loader
        private let writer: Writer

        public init(loader: @escaping Loader, writer: @escaping Writer) {
            self.loader = loader
            self.writer = writer
        }

        func load(tier: Tier, maxAge: TimeInterval) async throws -> UInt64? {
            try await loader(tier, maxAge)
        }

        func store(tier: Tier, value: UInt64, ttl: TimeInterval) async throws {
            try await writer(tier, value, ttl)
        }

        static var noop: Persistence {
            Persistence(loader: { _, _ in nil }, writer: { _, _, _ in })
        }
    }
}

#if canImport(SwiftData)
extension Network.Wallet.FeeRate.Persistence {
    static func storage(repository: Storage.Repository.Fees) -> Self {
        Self(loader: { tier, maxAge in
            try await repository.latest(tier.storageTier, maxAge: maxAge)?.satsPerByte
        },
             writer: { tier, value, ttl in
            try await repository.put(tier: tier.storageTier, satsPerByte: value, ttl: ttl)
        })
    }
}
#endif
