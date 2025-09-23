// Network+Gateway+Client_.swift

import Foundation

extension Network.Gateway {
    public protocol Client: Sendable {
        var currentMempool: Set<Transaction.Hash> { get set }
        func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash
        func fetch(_ hash: Transaction.Hash) async throws -> Transaction?
        func getRawTransaction(for hash: Transaction.Hash) async throws -> Data
        func getDetailedTransaction(for hash: Transaction.Hash) async throws -> Transaction.Detailed
        func getEstimateFee(targetBlocks: Int) async throws -> Satoshi
        func getRelayFee() async throws -> Satoshi
        func getHeader(height: UInt32) async throws -> Network.Gateway.HeaderPayload?
        func pingHeadersTip() async throws
        func interpretBroadcastError(_ error: Swift.Error, expectedHash: Transaction.Hash) -> Network.Gateway.BroadcastResolution?
        func normalize(error: Swift.Error, during request: Network.Gateway.Request) -> Network.Gateway.Error?
    }
}

extension Network.Gateway.Client {
    public func interpretBroadcastError(
        _ error: Swift.Error,
        expectedHash: Transaction.Hash
    ) -> Network.Gateway.BroadcastResolution? {
        nil
    }
    
    public func normalize(
        error: Swift.Error,
        during _: Network.Gateway.Request
    ) -> Network.Gateway.Error? {
        nil
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
