// Network+Gateway+API.swift

import Foundation

extension Network.Gateway {
    public struct API: Sendable {
        public typealias BroadcastClosure = @Sendable (_ transaction: Transaction) async throws -> Transaction.Hash
        public typealias FetchClosure = @Sendable (_ hash: Transaction.Hash) async throws -> Transaction?
        public typealias RawTransactionClosure = @Sendable (_ hash: Transaction.Hash) async throws -> Data
        public typealias DetailedTransactionClosure = @Sendable (_ hash: Transaction.Hash) async throws -> Transaction.Detailed
        public typealias EstimateFeeClosure = @Sendable (_ targetBlocks: Int) async throws -> Satoshi
        public typealias RelayFeeClosure = @Sendable () async throws -> Satoshi
        public typealias HeaderClosure = @Sendable (_ height: UInt32) async throws -> HeaderPayload?
        public typealias PingHeadersClosure = @Sendable () async throws -> Void
        public typealias InterpretBroadcastErrorClosure = @Sendable (_ error: Swift.Error, _ expectedHash: Transaction.Hash) -> BroadcastResolution?
        public typealias NormalizeClosure = @Sendable (_ error: Swift.Error, _ request: Network.Gateway.Request) -> Network.Gateway.Error?
        
        public let currentMempool: @Sendable () -> Set<Transaction.Hash>
        public let broadcast: BroadcastClosure
        public let fetch: FetchClosure
        public let getRawTransaction: RawTransactionClosure
        public let getDetailedTransaction: DetailedTransactionClosure
        public let getEstimateFee: EstimateFeeClosure
        public let getRelayFee: RelayFeeClosure
        public let getHeader: HeaderClosure
        public let pingHeadersTip: PingHeadersClosure
        
        private let interpretBroadcastErrorClosure: InterpretBroadcastErrorClosure
        private let normalizeClosure: NormalizeClosure
        
        public init(
            currentMempool: @escaping @Sendable () -> Set<Transaction.Hash> = { [] },
            broadcast: @escaping BroadcastClosure,
            fetch: @escaping FetchClosure,
            getRawTransaction: @escaping RawTransactionClosure,
            getDetailedTransaction: @escaping DetailedTransactionClosure,
            getEstimateFee: @escaping EstimateFeeClosure,
            getRelayFee: @escaping RelayFeeClosure,
            getHeader: @escaping HeaderClosure,
            pingHeadersTip: @escaping PingHeadersClosure,
            interpretBroadcastError: @escaping InterpretBroadcastErrorClosure = { _, _ in nil },
            normalize: @escaping NormalizeClosure = { _, _ in nil }
        ) {
            self.currentMempool = currentMempool
            self.broadcast = broadcast
            self.fetch = fetch
            self.getRawTransaction = getRawTransaction
            self.getDetailedTransaction = getDetailedTransaction
            self.getEstimateFee = getEstimateFee
            self.getRelayFee = getRelayFee
            self.getHeader = getHeader
            self.pingHeadersTip = pingHeadersTip
            self.interpretBroadcastErrorClosure = interpretBroadcastError
            self.normalizeClosure = normalize
        }
        
        public func interpretBroadcastError(
            _ error: Swift.Error,
            expectedHash: Transaction.Hash
        ) -> Network.Gateway.BroadcastResolution? {
            interpretBroadcastErrorClosure(error, expectedHash)
        }
        
        public func normalize(
            _ error: Swift.Error,
            during request: Network.Gateway.Request
        ) -> Network.Gateway.Error? {
            normalizeClosure(error, request)
        }
    }
}

extension Network.Gateway {
    public struct HeaderPayload: Sendable {
        public let identifier: UUID
        public let raw: Data
        
        public init(identifier: UUID, raw: Data) {
            self.identifier = identifier
            self.raw = raw
        }
    }
}
