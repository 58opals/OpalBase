// CashTokensMetadataRepositoryValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("CashTokens metadata repository", .tags(.unit, .cashTokens))
struct CashTokensMetadataRepositoryValidator {
    @Test("metadata initializer rejects unsafe URL surfaces")
    func metadataInitializerRejectsUnsafeURLSurfaces() throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x54, count: 32)
        )
        let iconURL = try #require(URL(string: "https://user:secret@example.com/icon.png"))
        let webURL = try #require(URL(string: "ipfs://bafybeigdyrzt/../token.json"))
        let registryURL = try #require(URL(string: "https://example.com/%252e%252e/registry.json"))

        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Unsafe Token",
            symbol: "UNSAFE",
            decimals: 0,
            iconURL: iconURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(registryURL),
            webURL: webURL,
            registryURL: registryURL
        )

        #expect(metadata.iconURL == nil)
        #expect(metadata.webURL == nil)
        #expect(metadata.registryURL == nil)
        #expect(metadata.source == .embedded)
    }

    @Test("metadata decoder rejects unsafe URL surfaces")
    func metadataDecoderRejectsUnsafeURLSurfaces() throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x55, count: 32)
        )
        let iconURL = try #require(URL(string: "https://user:secret@example.com/icon.png"))
        let webURL = try #require(URL(string: "ipfs://bafybeigdyrzt/../token.json"))
        let registryURL = try #require(URL(string: "https://example.com/%252e%252e/registry.json"))
        let payload = MetadataDecodePayload(
            category: category,
            name: "Decoded Unsafe Token",
            symbol: "DUNSAFE",
            decimals: -1,
            iconURL: iconURL,
            description: nil,
            webURL: webURL,
            identity: nil,
            authbase: nil,
            registryURL: registryURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(registryURL)
        )
        let encodedPayload = try JSONEncoder().encode(payload)

        let metadata = try JSONDecoder().decode(
            OpalBase.CashTokens.Metadata.self,
            from: encodedPayload
        )

        #expect(metadata.decimals == nil)
        #expect(metadata.iconURL == nil)
        #expect(metadata.webURL == nil)
        #expect(metadata.registryURL == nil)
        #expect(metadata.source == .embedded)
    }

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

    @Test("metadata repository rejects unsafe URL surfaces", arguments: MetadataUnsafeURLSurfaceCase.allCases)
    func metadataRepositoryRejectsUnsafeURLSurfaces(_ unsafeURLSurfaceCase: MetadataUnsafeURLSurfaceCase) async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: unsafeURLSurfaceCase.categoryByte, count: 32)
        )
        let iconURL = try #require(URL(string: unsafeURLSurfaceCase.iconURLString))
        let sourceURL = try #require(URL(string: unsafeURLSurfaceCase.sourceURLString))
        let webURL = try #require(URL(string: unsafeURLSurfaceCase.webURLString))
        let registryURL = try #require(URL(string: unsafeURLSurfaceCase.registryURLString))
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: unsafeURLSurfaceCase.name,
            symbol: unsafeURLSurfaceCase.symbol,
            decimals: 0,
            iconURL: iconURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(sourceURL),
            webURL: webURL,
            registryURL: registryURL
        )

        try await assertRepositoryRejectsUnsafeURLSurfaces(metadata, for: category)
    }

    @Test("metadata repository rejects traversal authorities", arguments: MetadataTraversalAuthorityCase.allCases)
    func metadataRepositoryRejectsTraversalAuthorities(
        _ traversalAuthorityCase: MetadataTraversalAuthorityCase
    ) async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: traversalAuthorityCase.categoryByte, count: 32)
        )
        let dotAuthorityURL = try #require(URL(string: traversalAuthorityCase.dotAuthorityURLString))
        let dotDotAuthorityURL = try #require(URL(string: traversalAuthorityCase.dotDotAuthorityURLString))
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: traversalAuthorityCase.name,
            symbol: traversalAuthorityCase.symbol,
            decimals: 0,
            iconURL: dotAuthorityURL,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .dns(dotDotAuthorityURL),
            webURL: dotDotAuthorityURL,
            registryURL: dotDotAuthorityURL
        )

        try await assertRepositoryRejectsUnsafeURLSurfaces(metadata, for: category)
    }

    @Test("metadata snapshot restore keeps the newest duplicate decoded category")
    func metadataSnapshotRestoreKeepsNewestDuplicateDecodedCategory() async throws {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0xab, count: 32)
        )
        let olderMetadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Older Token",
            symbol: "OLD",
            decimals: 0,
            iconURL: nil,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .embedded
        )
        let newerMetadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Newer Token",
            symbol: "NEW",
            decimals: 0,
            iconURL: nil,
            lastUpdated: Date(timeIntervalSince1970: 1),
            source: .embedded
        )
        let snapshot = OpalBase.CashTokens.MetadataRepository.Snapshot(
            byCategory: [
                category.hexForDisplay: olderMetadata,
                category.hexForDisplay.uppercased(): newerMetadata
            ]
        )
        let repository = OpalBase.CashTokens.MetadataRepository()

        await repository.applySnapshot(snapshot)

        let restored = try #require(await repository.fetchMetadata(for: category))
        #expect(restored.name == "Newer Token")
        #expect(restored.symbol == "NEW")
        #expect(restored.category == category)
    }

    private func assertRepositoryRejectsUnsafeURLSurfaces(
        _ metadata: OpalBase.CashTokens.Metadata,
        for category: OpalBase.CashTokens.CategoryID
    ) async throws {
        let repository = OpalBase.CashTokens.MetadataRepository()
        await repository.upsert([category: metadata])
        let fetchedMetadata = try #require(await repository.fetchMetadata(for: category))
        #expect(fetchedMetadata.iconURL == nil)
        #expect(fetchedMetadata.webURL == nil)
        #expect(fetchedMetadata.registryURL == nil)
        #expect(fetchedMetadata.source == .embedded)
    }

    private struct MetadataDecodePayload: Encodable {
        let category: OpalBase.CashTokens.CategoryID
        let name: String?
        let symbol: String?
        let decimals: Int?
        let iconURL: URL?
        let description: String?
        let webURL: URL?
        let identity: String?
        let authbase: OpalBase.Transaction.Hash?
        let registryURL: URL?
        let lastUpdated: Date
        let source: OpalBase.CashTokens.Metadata.Source
    }

    enum MetadataUnsafeURLSurfaceCase: CaseIterable, Sendable {
        case embeddedCredentials
        case interPlanetaryFileSystemPathTraversal
        case hypertextTransferProtocolSecurePathTraversal
        case invalidPort
        case malformedInternetProtocolLiteral
        case malformedInternetProtocolVersion4Literal
        case malformedRootQualifiedInternetProtocolVersion4Literal
        case malformedRepeatedRootQualifiedInternetProtocolVersion4Literal

        var categoryByte: UInt8 {
            switch self {
            case .embeddedCredentials:
                return 0x4e
            case .interPlanetaryFileSystemPathTraversal:
                return 0x4f
            case .hypertextTransferProtocolSecurePathTraversal:
                return 0x53
            case .invalidPort:
                return 0x50
            case .malformedInternetProtocolLiteral:
                return 0x56
            case .malformedInternetProtocolVersion4Literal:
                return 0x57
            case .malformedRootQualifiedInternetProtocolVersion4Literal:
                return 0x58
            case .malformedRepeatedRootQualifiedInternetProtocolVersion4Literal:
                return 0x59
            }
        }

        var iconURLString: String {
            switch self {
            case .embeddedCredentials:
                return "https://user:secret@example.com/icon.png"
            case .interPlanetaryFileSystemPathTraversal:
                return "ipfs:///bafybeigdyrzt/../icon.png"
            case .hypertextTransferProtocolSecurePathTraversal:
                return "https://example.com/../icon.png"
            case .invalidPort:
                return "https://example.com:0/icon.png"
            case .malformedInternetProtocolLiteral:
                return "https://[::::]/icon.png"
            case .malformedInternetProtocolVersion4Literal:
                return "https://999.999.999.999/icon.png"
            case .malformedRootQualifiedInternetProtocolVersion4Literal:
                return "https://999.999.999.999./icon.png"
            case .malformedRepeatedRootQualifiedInternetProtocolVersion4Literal:
                return "https://999.999.999.999../icon.png"
            }
        }

        var sourceURLString: String {
            switch self {
            case .embeddedCredentials:
                return iconURLString
            case .interPlanetaryFileSystemPathTraversal:
                return registryURLString
            case .hypertextTransferProtocolSecurePathTraversal:
                return registryURLString
            case .invalidPort:
                return registryURLString
            case .malformedInternetProtocolLiteral:
                return registryURLString
            case .malformedInternetProtocolVersion4Literal:
                return registryURLString
            case .malformedRootQualifiedInternetProtocolVersion4Literal:
                return registryURLString
            case .malformedRepeatedRootQualifiedInternetProtocolVersion4Literal:
                return registryURLString
            }
        }

        var webURLString: String {
            switch self {
            case .embeddedCredentials:
                return "ipfs://user@bafybeigdyrzt/token.json"
            case .interPlanetaryFileSystemPathTraversal:
                return "ipfs://bafybeigdyrzt/../secret.json"
            case .hypertextTransferProtocolSecurePathTraversal:
                return "https://example.com/%252e%252e%252ftoken.json"
            case .invalidPort:
                return registryURLString
            case .malformedInternetProtocolLiteral:
                return "ipfs://[::::]/token.json"
            case .malformedInternetProtocolVersion4Literal:
                return "ipfs://999.999.999.999/token.json"
            case .malformedRootQualifiedInternetProtocolVersion4Literal:
                return "ipfs://999.999.999.999./token.json"
            case .malformedRepeatedRootQualifiedInternetProtocolVersion4Literal:
                return "ipfs://999.999.999.999../token.json"
            }
        }

        var registryURLString: String {
            switch self {
            case .embeddedCredentials:
                return iconURLString
            case .interPlanetaryFileSystemPathTraversal:
                return "ipfs://bafybeigdyrzt/%252e%252e/registry.json"
            case .hypertextTransferProtocolSecurePathTraversal:
                return "https://example.com/%2e%2e/registry.json"
            case .invalidPort:
                return "https://example.com:65536/registry.json"
            case .malformedInternetProtocolLiteral:
                return "https://[::::]/registry.json"
            case .malformedInternetProtocolVersion4Literal:
                return "https://999.999.999.999/registry.json"
            case .malformedRootQualifiedInternetProtocolVersion4Literal:
                return "https://999.999.999.999./registry.json"
            case .malformedRepeatedRootQualifiedInternetProtocolVersion4Literal:
                return "https://999.999.999.999../registry.json"
            }
        }

        var name: String {
            switch self {
            case .embeddedCredentials:
                return "Credential Token"
            case .interPlanetaryFileSystemPathTraversal:
                return "Traversal Token"
            case .hypertextTransferProtocolSecurePathTraversal:
                return "HTTPS Path Traversal Token"
            case .invalidPort:
                return "Invalid Port Token"
            case .malformedInternetProtocolLiteral:
                return "Malformed IP Literal Token"
            case .malformedInternetProtocolVersion4Literal:
                return "Malformed IPv4 Literal Token"
            case .malformedRootQualifiedInternetProtocolVersion4Literal:
                return "Malformed Root-Qualified IPv4 Literal Token"
            case .malformedRepeatedRootQualifiedInternetProtocolVersion4Literal:
                return "Malformed Repeated Root-Qualified IPv4 Literal Token"
            }
        }

        var symbol: String {
            switch self {
            case .embeddedCredentials:
                return "CRED"
            case .interPlanetaryFileSystemPathTraversal:
                return "TRAV"
            case .hypertextTransferProtocolSecurePathTraversal:
                return "HTTPSPATH"
            case .invalidPort:
                return "PORT"
            case .malformedInternetProtocolLiteral:
                return "BADIP"
            case .malformedInternetProtocolVersion4Literal:
                return "BADIPv4"
            case .malformedRootQualifiedInternetProtocolVersion4Literal:
                return "BADFQDNIPv4"
            case .malformedRepeatedRootQualifiedInternetProtocolVersion4Literal:
                return "BADFQDNIPv4X"
            }
        }
    }

    enum MetadataTraversalAuthorityCase: CaseIterable, Sendable {
        case interPlanetaryFileSystem
        case hypertextTransferProtocolSecure

        var categoryByte: UInt8 {
            switch self {
            case .interPlanetaryFileSystem:
                return 0x51
            case .hypertextTransferProtocolSecure:
                return 0x52
            }
        }

        var dotAuthorityURLString: String {
            switch self {
            case .interPlanetaryFileSystem:
                return "ipfs://./icon.png"
            case .hypertextTransferProtocolSecure:
                return "https://./icon.png"
            }
        }

        var dotDotAuthorityURLString: String {
            switch self {
            case .interPlanetaryFileSystem:
                return "ipfs://../registry.json"
            case .hypertextTransferProtocolSecure:
                return "https://../registry.json"
            }
        }

        var name: String {
            switch self {
            case .interPlanetaryFileSystem:
                return "Traversal Authority Token"
            case .hypertextTransferProtocolSecure:
                return "HTTPS Traversal Authority Token"
            }
        }

        var symbol: String {
            switch self {
            case .interPlanetaryFileSystem:
                return "TRAVAUTH"
            case .hypertextTransferProtocolSecure:
                return "HTTPTA"
            }
        }
    }
}
