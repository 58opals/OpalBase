// WalletTokenMetadataSyncValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalBase

@Suite("Wallet token metadata sync", .tags(.unit, .cashTokens), .serialized)
struct WalletTokenMetadataSyncValidator {
    @Test("syncTokenMetadata resolves fungible and NFT-only inventory categories")
    func syncTokenMetadataResolvesFungibleAndNonFungibleInventoryCategories() async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let account = try await wallet.fetchAccount(at: 0)
        let fungibleAuthbase = try makeTokenMetadataSyncAuthbase(byte: 0x91)
        let nonFungibleAuthbase = try makeTokenMetadataSyncAuthbase(byte: 0x92)
        let fungibleCategory = fungibleAuthbase.category
        let nonFungibleCategory = nonFungibleAuthbase.category
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 1_000,
            tokenData: OpalBase.CashTokens.TokenData(
                category: fungibleCategory,
                amount: 123,
                nft: nil
            ),
            hashByte: 0x41
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 1_000,
            tokenData: OpalBase.CashTokens.TokenData(
                category: nonFungibleCategory,
                amount: nil,
                nft: try OpalBase.CashTokens.NFT(
                    capability: .none,
                    commitment: Data([0x01, 0x02])
                )
            ),
            hashByte: 0x42
        )

        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "fungible.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Fungible Token",
                        description: nil,
                        token: .init(
                            category: fungibleCategory.hexForDisplay,
                            symbol: "FUNG",
                            decimals: 2
                        ),
                        uris: nil
                    )
                ],
                "nft.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "NFT Collection",
                        description: nil,
                        token: .init(
                            category: nonFungibleCategory.hexForDisplay,
                            symbol: "NFT",
                            decimals: 0
                        ),
                        uris: nil
                    )
                ]
            ]
        )
        let registryData = try JSONEncoder().encode(registry)
        let registryURL = try #require(URL(string: "https://registry.example/metadata.json"))
        let publicationScript = makeTokenMetadataSyncPublicationScript(
            registryData: registryData,
            registryURL: registryURL
        )
        let authchain = try makeTokenMetadataSyncAuthchain(
            authbases: [fungibleAuthbase, nonFungibleAuthbase],
            publicationScript: publicationScript
        )
        try await withTokenMetadataSyncRegistryFetcher(registryData: registryData) { registryFetcher in
            try await wallet.syncTokenMetadata(
                using: authchain.transactionReader,
                addressReader: authchain.addressReader,
                registryFetcher: registryFetcher
            )
        }

        let fungibleMetadata = try #require(await wallet.fetchTokenMetadata(for: fungibleCategory))
        let nonFungibleMetadata = try #require(await wallet.fetchTokenMetadata(for: nonFungibleCategory))
        #expect(fungibleMetadata.name == "Fungible Token")
        #expect(fungibleMetadata.symbol == "FUNG")
        #expect(fungibleMetadata.registryURL == registryURL)
        #expect(nonFungibleMetadata.name == "NFT Collection")
        #expect(nonFungibleMetadata.symbol == "NFT")
        #expect(nonFungibleMetadata.registryURL == registryURL)
    }

    @Test("syncTokenMetadata stores only requested categories")
    func syncTokenMetadataStoresOnlyRequestedCategories() async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let targetAuthbase = try makeTokenMetadataSyncAuthbase(byte: 0x93)
        let targetCategory = targetAuthbase.category
        let unrelatedCategory = try makeTokenMetadataSyncCategory(byte: 0x94)
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "target.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Target Token",
                        description: nil,
                        token: .init(
                            category: targetCategory.hexForDisplay,
                            symbol: "TARGET",
                            decimals: 2
                        ),
                        uris: nil
                    )
                ],
                "unrelated.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Unrelated Token",
                        description: nil,
                        token: .init(
                            category: unrelatedCategory.hexForDisplay,
                            symbol: "OTHER",
                            decimals: 0
                        ),
                        uris: nil
                    )
                ]
            ]
        )
        let registryData = try JSONEncoder().encode(registry)
        let registryURL = try #require(URL(string: "https://registry.example/metadata.json"))
        let publicationScript = makeTokenMetadataSyncPublicationScript(
            registryData: registryData,
            registryURL: registryURL
        )
        let authchain = try makeTokenMetadataSyncAuthchain(
            authbases: [targetAuthbase],
            publicationScript: publicationScript
        )
        try await withTokenMetadataSyncRegistryFetcher(registryData: registryData) { registryFetcher in
            try await wallet.syncTokenMetadata(
                using: authchain.transactionReader,
                addressReader: authchain.addressReader,
                categories: [targetCategory],
                registryFetcher: registryFetcher
            )
        }

        let targetMetadata = try #require(await wallet.fetchTokenMetadata(for: targetCategory))
        #expect(targetMetadata.name == "Target Token")
        #expect(await wallet.fetchTokenMetadata(for: unrelatedCategory) == nil)
    }

    @Test(
        "syncTokenMetadata propagates cancellation",
        arguments: TokenMetadataSyncCancellationCase.allCases
    )
    func syncTokenMetadataPropagatesCancellation(
        _ cancellationCase: TokenMetadataSyncCancellationCase
    ) async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let category = try makeTokenMetadataSyncCategory(byte: cancellationCase.categoryByte)
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            throw cancellationCase.makeError()
        }
        let publicationHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: cancellationCase.publicationHashByte, count: 32)
        )

        await #expect(throws: CancellationError.self) {
            try await wallet.syncTokenMetadata(
                using: transactionReader,
                addressReader: makeTokenMetadataSyncAddressReader(publicationHash: publicationHash),
                categories: [category]
            )
        }
    }
}

private struct TokenMetadataSyncAuthbase: Sendable {
    let rawTransaction: Data
    let transactionHash: OpalBase.Transaction.Hash
    let category: OpalBase.CashTokens.CategoryID
}

private struct TokenMetadataSyncAuthchain: Sendable {
    let transactionReader: OpalBase.Network.TransactionReader
    let addressReader: OpalBase.Network.AddressReader
}

enum TokenMetadataSyncCancellationCase: CaseIterable, Sendable {
    case direct
    case url

    var categoryByte: UInt8 {
        switch self {
        case .direct:
            return 0x95
        case .url:
            return 0x97
        }
    }

    var publicationHashByte: UInt8 {
        switch self {
        case .direct:
            return 0x96
        case .url:
            return 0x98
        }
    }

    func makeError() -> Swift.Error {
        switch self {
        case .direct:
            return CancellationError()
        case .url:
            return NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorCancelled
            )
        }
    }
}

private func makeTokenMetadataSyncAuthbase(byte: UInt8) throws -> TokenMetadataSyncAuthbase {
    let identityAddress = try OpalBase.Address(string: AccountTestFixtures.standardAddressString)
    let input = OpalBase.Transaction.Input(
        previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: byte, count: 32)),
        previousTransactionOutputIndex: 0,
        unlockingScript: Data()
    )
    let transaction = OpalBase.Transaction(
        version: 1,
        inputs: [input],
        outputs: [
            OpalBase.Transaction.Output(
                value: 1,
                lockingScript: identityAddress.lockingScript.data
            )
        ],
        lockTime: 0
    )
    let rawTransaction = try transaction.encode()
    let transactionHash = OpalBase.Transaction.Hash(
        naturalOrder: OpalCryptoAdapter.hash256(rawTransaction)
    )
    return try TokenMetadataSyncAuthbase(
        rawTransaction: rawTransaction,
        transactionHash: transactionHash,
        category: OpalBase.CashTokens.CategoryID(transactionOrderData: transactionHash.naturalOrder)
    )
}

private func makeTokenMetadataSyncCategory(byte: UInt8) throws -> OpalBase.CashTokens.CategoryID {
    try OpalBase.CashTokens.CategoryID(
        hexFromRPC: Data(repeating: byte, count: 32).hexadecimalString
    )
}

private func makeTokenMetadataSyncAuthchain(
    authbases: [TokenMetadataSyncAuthbase],
    publicationScript: Data
) throws -> TokenMetadataSyncAuthchain {
    let rawPublicationTransaction = try makeTokenMetadataSyncPublicationTransaction(
        authbaseHashes: authbases.map(\.transactionHash),
        publicationScript: publicationScript
    )
    let publicationHash = OpalBase.Transaction.Hash(
        naturalOrder: OpalCryptoAdapter.hash256(rawPublicationTransaction)
    )
    var mutableRawTransactionsByHash = Dictionary(
        uniqueKeysWithValues: authbases.map { authbase in
            (authbase.transactionHash, authbase.rawTransaction)
        }
    )
    mutableRawTransactionsByHash[publicationHash] = rawPublicationTransaction
    let rawTransactionsByHash = mutableRawTransactionsByHash

    let transactionReader = OpalBase.Network.TransactionReader { transactionHash in
        guard let rawTransaction = rawTransactionsByHash[transactionHash] else {
            throw TokenMetadataSyncStubError.notImplemented
        }
        return rawTransaction
    }

    return TokenMetadataSyncAuthchain(
        transactionReader: transactionReader,
        addressReader: makeTokenMetadataSyncAddressReader(publicationHash: publicationHash)
    )
}

private func makeTokenMetadataSyncAddressReader(
    publicationHash: OpalBase.Transaction.Hash
) -> OpalBase.Network.AddressReader {
    OpalBase.Network.AddressReader(
        fetchBalance: { _, _ in throw TokenMetadataSyncStubError.notImplemented },
        fetchUnspentOutputs: { _, _ in throw TokenMetadataSyncStubError.notImplemented },
        fetchHistory: { _, _ in
            [
                OpalBase.Network.TransactionHistoryEntry(
                    transactionIdentifier: publicationHash.reverseOrder.hexadecimalString,
                    blockHeight: 1,
                    fee: nil
                )
            ]
        },
        fetchFirstUse: { _ in nil },
        fetchMempoolTransactions: { _ in [] },
        fetchScriptHash: { _ in throw TokenMetadataSyncStubError.notImplemented },
        subscribeToAddress: { _ in
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    )
}

private func makeTokenMetadataSyncPublicationScript(
    registryData: Data,
    registryURL: URL
) -> Data {
    let prefix = Data([0x42, 0x43, 0x4d, 0x52])
    var script = Data([0x6a])
    script.append(Data.push(prefix))
    script.append(Data.push(OpalCrypto.Hashing.sha256(registryData)))
    script.append(Data.push(Data(registryURL.absoluteString.utf8)))
    return script
}

private func makeTokenMetadataSyncPublicationTransaction(
    authbaseHashes: [OpalBase.Transaction.Hash],
    publicationScript: Data
) throws -> Data {
    let identityAddress = try OpalBase.Address(string: AccountTestFixtures.standardAddressString)
    let transaction = OpalBase.Transaction(
        version: 1,
        inputs: authbaseHashes.map { authbaseHash in
            OpalBase.Transaction.Input(
                previousTransactionHash: authbaseHash,
                previousTransactionOutputIndex: 0,
                unlockingScript: Data()
            )
        },
        outputs: [
            OpalBase.Transaction.Output(
                value: 1,
                lockingScript: identityAddress.lockingScript.data
            ),
            OpalBase.Transaction.Output(
                value: 0,
                lockingScript: publicationScript
            )
        ],
        lockTime: 0
    )
    return try transaction.encode()
}

private func withTokenMetadataSyncRegistryFetcher<T>(
    registryData: Data,
    operation: (OpalBase.CashTokens.BCMR.Client.Fetcher) async throws -> T
) async throws -> T {
    let session = makeTokenMetadataSyncRegistrySession { request in
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        return (response, registryData)
    }
    defer {
        TokenMetadataSyncRegistryURLProtocol.requestHandler = nil
        session.invalidateAndCancel()
    }
    let registryFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
        urlSession: session,
        maxBytes: 64 * 1_024
    )
    return try await operation(registryFetcher)
}

private func makeTokenMetadataSyncRegistrySession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TokenMetadataSyncRegistryURLProtocol.self]
    let session = URLSession(configuration: configuration)
    TokenMetadataSyncRegistryURLProtocol.requestHandler = { request in
        return try handler(request)
    }
    return session
}
