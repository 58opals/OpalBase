// BitcoinCashMetadataRegistryTestClient.swift

import Foundation
@testable import OpalBase

enum BitcoinCashMetadataRegistryTestClient {
    static func makeRegistries() -> BitcoinCashMetadataRegistryClient {
        let authchainResolver = BitcoinCashMetadataRegistryClient.AuthchainResolverModel(
            transactionReader: PlaceholderTransactionReaderModel(),
            addressReader: PlaceholderAddressReaderModel(),
            maxDepth: 0
        )
        let registryFetcher = BitcoinCashMetadataRegistryClient.FetcherModel(maxBytes: 1_024)
        return BitcoinCashMetadataRegistryClient(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )
    }
}

private enum PlaceholderNetworkError: Swift.Error {
    case notImplemented
}

private struct PlaceholderTransactionReaderModel: OpalBase.Network.TransactionReadableClient {
    func fetchRawTransaction(for transactionHash: OpalBase.Transaction.HashModel) async throws -> Data {
        throw PlaceholderNetworkError.notImplemented
    }
}

private struct PlaceholderAddressReaderModel: OpalBase.Network.AddressReadable {
    func fetchBalance(
        for address: String,
        tokenFilter: OpalBase.Network.TokenFilter
    ) async throws -> OpalBase.Network.AddressBalance {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchUnspentOutputs(
        for address: String,
        tokenFilter: OpalBase.Network.TokenFilter
    ) async throws -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchHistory(
        for address: String,
        includeUnconfirmed: Bool
    ) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchMempoolTransactions(
        for address: String
    ) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func fetchScriptHash(for address: String) async throws -> String {
        throw PlaceholderNetworkError.notImplemented
    }
    
    func subscribeToAddress(
        _ address: String
    ) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: PlaceholderNetworkError.notImplemented)
        }
    }
}

