// CashTokensMetadataRepositoryValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("CashTokens metadata repository", .tags(.unit, .cashTokens))
struct CashTokensMetadataRepositoryValidator {
    @Test("metadata repository preserves path-form IPFS URLs")
    func metadataRepositoryPreservesPathFormInterPlanetaryFileSystemURLs() async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x4d, count: 32)
        )
        let iconURL = try #require(URL(string: "ipfs:///bafybeigdyrzt/icon.png"))
        let registryURL = try #require(URL(string: "ipfs://bafybeigdyrzt/registry.json"))
        let repository = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Repository Token",
            symbol: "REPO",
            decimals: 0,
            iconURL: iconURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .embedded,
            registryURL: registryURL
        )

        await repository.upsert([category: metadata])

        let fetchedMetadata = try #require(await repository.fetchMetadata(for: category))
        #expect(fetchedMetadata.iconURL == iconURL)
        #expect(fetchedMetadata.registryURL == registryURL)
    }

    @Test("metadata repository rejects URLs with embedded credentials")
    func metadataRepositoryRejectsURLsWithEmbeddedCredentials() async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x4e, count: 32)
        )
        let iconURL = try #require(URL(string: "https://user:secret@example.com/icon.png"))
        let webURL = try #require(URL(string: "ipfs://user@bafybeigdyrzt/token.json"))
        let repository = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Credential Token",
            symbol: "CRED",
            decimals: 0,
            iconURL: iconURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(iconURL),
            webURL: webURL,
            registryURL: iconURL
        )

        await repository.upsert([category: metadata])

        let fetchedMetadata = try #require(await repository.fetchMetadata(for: category))
        #expect(fetchedMetadata.iconURL == nil)
        #expect(fetchedMetadata.webURL == nil)
        #expect(fetchedMetadata.registryURL == nil)
        #expect(fetchedMetadata.source == .embedded)
    }
}
