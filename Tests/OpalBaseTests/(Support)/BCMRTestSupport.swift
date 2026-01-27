import Foundation
@testable import OpalBase

enum BCMRTestSupport {
    static func makeRegistries() -> BitcoinCashMetadataRegistries {
        let authchainResolver = BitcoinCashMetadataRegistries.AuthchainResolver(
            transactionReader: PlaceholderTransactionReader(),
            addressReader: PlaceholderAddressReader(),
            maxDepth: 0
        )
        let registryFetcher = BitcoinCashMetadataRegistries.Fetcher(maxBytes: 1_024)
        return BitcoinCashMetadataRegistries(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )
    }
}

private enum PlaceholderNetworkError: Swift.Error {
    case notImplemented
}

private struct PlaceholderTransactionReader: Network.TransactionReadable {
    func fetchRawTransaction(for transactionHash: Transaction.Hash) async throws -> Data {
        throw PlaceholderNetworkError.notImplemented
    }
}

private struct PlaceholderAddressReader: Network.AddressReadable {
    func fetchBalance(
        for address: String,
        tokenFilter: Network.TokenFilter
    ) async throws -> Network.AddressBalance {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchUnspentOutputs(
        for address: String,
        tokenFilter: Network.TokenFilter
    ) async throws -> [Transaction.Output.Unspent] {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchHistory(
        for address: String,
        includeUnconfirmed: Bool
    ) async throws -> [Network.TransactionHistoryEntry] {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchFirstUse(for address: String) async throws -> Network.AddressFirstUse? {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchMempoolTransactions(
        for address: String
    ) async throws -> [Network.TransactionHistoryEntry] {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchScriptHash(for address: String) async throws -> String {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func subscribeToAddress(
        _ address: String
    ) async throws -> AsyncThrowingStream<Network.AddressSubscriptionUpdate, any Swift.Error> {
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: PlaceholderNetworkError.notImplemented)
        }
    }
}
