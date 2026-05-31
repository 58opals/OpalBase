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

    @Test("metadata repository rejects IPFS path traversal URLs")
    func metadataRepositoryRejectsInterPlanetaryFileSystemPathTraversalURLs() async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x4f, count: 32)
        )
        let hostedPathTraversalURL = try #require(URL(string: "ipfs://bafybeigdyrzt/../secret.json"))
        let pathFormTraversalURL = try #require(URL(string: "ipfs:///bafybeigdyrzt/../icon.png"))
        let encodedPathTraversalURL = try #require(URL(string: "ipfs://bafybeigdyrzt/%252e%252e/registry.json"))
        let repository = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Traversal Token",
            symbol: "TRAV",
            decimals: 0,
            iconURL: pathFormTraversalURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(encodedPathTraversalURL),
            webURL: hostedPathTraversalURL,
            registryURL: encodedPathTraversalURL
        )

        await repository.upsert([category: metadata])

        let fetchedMetadata = try #require(await repository.fetchMetadata(for: category))
        #expect(fetchedMetadata.iconURL == nil)
        #expect(fetchedMetadata.webURL == nil)
        #expect(fetchedMetadata.registryURL == nil)
        #expect(fetchedMetadata.source == .embedded)
    }

    @Test("metadata repository rejects IPFS traversal authorities")
    func metadataRepositoryRejectsInterPlanetaryFileSystemTraversalAuthorities() async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x51, count: 32)
        )
        let dotAuthorityURL = try #require(URL(string: "ipfs://./icon.png"))
        let dotDotAuthorityURL = try #require(URL(string: "ipfs://../registry.json"))
        let repository = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Traversal Authority Token",
            symbol: "TRAVAUTH",
            decimals: 0,
            iconURL: dotAuthorityURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(dotDotAuthorityURL),
            webURL: dotDotAuthorityURL,
            registryURL: dotDotAuthorityURL
        )

        await repository.upsert([category: metadata])

        let fetchedMetadata = try #require(await repository.fetchMetadata(for: category))
        #expect(fetchedMetadata.iconURL == nil)
        #expect(fetchedMetadata.webURL == nil)
        #expect(fetchedMetadata.registryURL == nil)
        #expect(fetchedMetadata.source == .embedded)
    }

    @Test("metadata repository rejects HTTPS traversal authorities")
    func metadataRepositoryRejectsHypertextTransferProtocolSecureTraversalAuthorities() async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x52, count: 32)
        )
        let dotAuthorityURL = try #require(URL(string: "https://./icon.png"))
        let dotDotAuthorityURL = try #require(URL(string: "https://../registry.json"))
        let repository = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "HTTPS Traversal Authority Token",
            symbol: "HTTPTA",
            decimals: 0,
            iconURL: dotAuthorityURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(dotDotAuthorityURL),
            webURL: dotDotAuthorityURL,
            registryURL: dotDotAuthorityURL
        )

        await repository.upsert([category: metadata])

        let fetchedMetadata = try #require(await repository.fetchMetadata(for: category))
        #expect(fetchedMetadata.iconURL == nil)
        #expect(fetchedMetadata.webURL == nil)
        #expect(fetchedMetadata.registryURL == nil)
        #expect(fetchedMetadata.source == .embedded)
    }

    @Test("metadata repository rejects HTTPS path traversal URLs")
    func metadataRepositoryRejectsHypertextTransferProtocolSecurePathTraversalURLs() async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x53, count: 32)
        )
        let iconURL = try #require(URL(string: "https://example.com/../icon.png"))
        let registryURL = try #require(URL(string: "https://example.com/%2e%2e/registry.json"))
        let encodedWebURL = try #require(URL(string: "https://example.com/%252e%252e/token.json"))
        let repository = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "HTTPS Path Traversal Token",
            symbol: "HTTPSPATH",
            decimals: 0,
            iconURL: iconURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(registryURL),
            webURL: encodedWebURL,
            registryURL: registryURL
        )

        await repository.upsert([category: metadata])

        let fetchedMetadata = try #require(await repository.fetchMetadata(for: category))
        #expect(fetchedMetadata.iconURL == nil)
        #expect(fetchedMetadata.webURL == nil)
        #expect(fetchedMetadata.registryURL == nil)
        #expect(fetchedMetadata.source == .embedded)
    }

    @Test("metadata repository rejects URLs with invalid ports")
    func metadataRepositoryRejectsURLsWithInvalidPorts() async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x50, count: 32)
        )
        let iconURL = try #require(URL(string: "https://example.com:0/icon.png"))
        let registryURL = try #require(URL(string: "https://example.com:65536/registry.json"))
        let repository = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Invalid Port Token",
            symbol: "PORT",
            decimals: 0,
            iconURL: iconURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(registryURL),
            webURL: registryURL,
            registryURL: registryURL
        )

        await repository.upsert([category: metadata])

        let fetchedMetadata = try #require(await repository.fetchMetadata(for: category))
        #expect(fetchedMetadata.iconURL == nil)
        #expect(fetchedMetadata.webURL == nil)
        #expect(fetchedMetadata.registryURL == nil)
        #expect(fetchedMetadata.source == .embedded)
    }
}
