// WalletTokenMetadataSyncValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet token metadata sync", .tags(.unit, .cashTokens), .serialized)
struct WalletTokenMetadataSyncValidator {
    @Test("syncTokenMetadata resolves fungible and NFT-only inventory categories")
    func syncTokenMetadataResolvesFungibleAndNonFungibleInventoryCategories() async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let account = try await wallet.fetchAccount(at: 0)
        let fungibleAuthbase = try TokenMetadataSyncFixture.makeAuthbase(byte: 0x91)
        let nonFungibleAuthbase = try TokenMetadataSyncFixture.makeAuthbase(byte: 0x92)
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
        let publicationScript = TokenMetadataSyncFixture.makePublicationScript(
            registryData: registryData,
            registryURL: registryURL
        )
        let authchain = try TokenMetadataSyncFixture.makeAuthchain(
            authbases: [fungibleAuthbase, nonFungibleAuthbase],
            publicationScript: publicationScript
        )
        try await TokenMetadataSyncFixture.withRegistryFetcher(registryData: registryData) { registryFetcher in
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
        let targetAuthbase = try TokenMetadataSyncFixture.makeAuthbase(byte: 0x93)
        let targetCategory = targetAuthbase.category
        let unrelatedCategory = try TokenMetadataSyncFixture.makeCategory(byte: 0x94)
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
        let publicationScript = TokenMetadataSyncFixture.makePublicationScript(
            registryData: registryData,
            registryURL: registryURL
        )
        let authchain = try TokenMetadataSyncFixture.makeAuthchain(
            authbases: [targetAuthbase],
            publicationScript: publicationScript
        )
        try await TokenMetadataSyncFixture.withRegistryFetcher(registryData: registryData) { registryFetcher in
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
        let category = try TokenMetadataSyncFixture.makeCategory(byte: cancellationCase.categoryByte)
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            throw cancellationCase.makeError()
        }
        let publicationHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: cancellationCase.publicationHashByte, count: 32)
        )

        await #expect(throws: CancellationError.self) {
            try await wallet.syncTokenMetadata(
                using: transactionReader,
                addressReader: TokenMetadataSyncFixture.makeAddressReader(publicationHash: publicationHash),
                categories: [category]
            )
        }
    }
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
