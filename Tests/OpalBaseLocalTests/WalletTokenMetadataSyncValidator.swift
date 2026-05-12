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
        let fungibleCategory = try makeTokenMetadataSyncCategory(byte: 0x91)
        let nonFungibleCategory = try makeTokenMetadataSyncCategory(byte: 0x92)
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
        let rawPublicationTransaction = try makeTokenMetadataSyncPublicationTransaction(
            publicationScript: publicationScript
        )
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            rawPublicationTransaction
        }
        let addressReader = makeTokenMetadataSyncAddressReader()
        let (session, _) = makeTokenMetadataSyncRegistrySession { request in
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

        try await wallet.syncTokenMetadata(
            using: transactionReader,
            addressReader: addressReader,
            registryFetcher: registryFetcher
        )

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
        let targetCategory = try makeTokenMetadataSyncCategory(byte: 0x93)
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
        let rawPublicationTransaction = try makeTokenMetadataSyncPublicationTransaction(
            publicationScript: publicationScript
        )
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            rawPublicationTransaction
        }
        let addressReader = makeTokenMetadataSyncAddressReader()
        let (session, _) = makeTokenMetadataSyncRegistrySession { request in
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

        try await wallet.syncTokenMetadata(
            using: transactionReader,
            addressReader: addressReader,
            categories: [targetCategory],
            registryFetcher: registryFetcher
        )

        let targetMetadata = try #require(await wallet.fetchTokenMetadata(for: targetCategory))
        #expect(targetMetadata.name == "Target Token")
        #expect(await wallet.fetchTokenMetadata(for: unrelatedCategory) == nil)
    }
}

private enum TokenMetadataSyncStubError: Swift.Error {
    case notImplemented
}

private func makeTokenMetadataSyncCategory(byte: UInt8) throws -> OpalBase.CashTokens.CategoryID {
    try OpalBase.CashTokens.CategoryID(
        hexFromRPC: Data(repeating: byte, count: 32).hexadecimalString
    )
}

private func makeTokenMetadataSyncAddressReader() -> OpalBase.Network.AddressReader {
    OpalBase.Network.AddressReader(
        fetchBalance: { _, _ in throw TokenMetadataSyncStubError.notImplemented },
        fetchUnspentOutputs: { _, _ in throw TokenMetadataSyncStubError.notImplemented },
        fetchHistory: { _, _ in [] },
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

private func makeTokenMetadataSyncPublicationTransaction(publicationScript: Data) throws -> Data {
    let identityAddress = try OpalBase.Address(string: AccountTestFixtures.standardAddressString)
    let input = OpalBase.Transaction.Input(
        previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x31),
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

private func makeTokenMetadataSyncRegistrySession(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
) -> (URLSession, TokenMetadataSyncRequestRecorder) {
    let recorder = TokenMetadataSyncRequestRecorder()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TokenMetadataSyncRegistryURLProtocol.self]
    let session = URLSession(configuration: configuration)
    TokenMetadataSyncRegistryURLProtocol.requestHandler = { request in
        if let url = request.url {
            recorder.append(url)
        }
        return try handler(request)
    }
    return (session, recorder)
}

private final class TokenMetadataSyncRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requestedURLs: [URL] = .init()

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requestedURLs
    }

    func append(_ url: URL) {
        lock.lock()
        requestedURLs.append(url)
        lock.unlock()
    }
}

private final class TokenMetadataSyncRegistryURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
