// BitcoinCashMetadataRegistryTestClient.swift

import Foundation
@testable import OpalBase

enum BitcoinCashMetadataRegistryTestClient {
    static func makeRegistries() -> OpalBase.CashTokens.BCMR.Client {
        let authchainResolver = OpalBase.CashTokens.BCMR.Client.AuthchainResolver(
            transactionReader: PlaceholderTransactionReader(),
            addressReader: PlaceholderAddressReader(),
            maxDepth: 0
        )
        let registryFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(maxBytes: 1_024)
        return OpalBase.CashTokens.BCMR.Client(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )
    }
}
