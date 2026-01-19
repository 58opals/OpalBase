// Network+AddressReadable_.swift

import Foundation

extension Network {
    public typealias AddressReadable = AddressQuerying & AddressSubscribing
    
    public protocol AddressQuerying: Sendable {
        func fetchBalance(for address: String) async throws -> AddressBalance
        func fetchUnspentOutputs(for address: String) async throws -> [Transaction.Output.Unspent]
        func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [TransactionHistoryEntry]
        func fetchFirstUse(for address: String) async throws -> AddressFirstUse?
        func fetchMempoolTransactions(for address: String) async throws -> [TransactionHistoryEntry]
        func fetchScriptHash(for address: String) async throws -> String
    }
    
    public protocol AddressSubscribing: Sendable {
        func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<AddressSubscriptionUpdate, any Swift.Error>
    }
}
