// TokenMetadataRepositorySnapshotValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Token metadata store snapshots", .tags(.unit, .cashTokens))
struct TokenMetadataRepositorySnapshotValidator {
    @Test("roundtrips store snapshots with metadata")
    func roundtripStoreSnapshotsWithMetadata() async throws {
        let store = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: try BitcoinCashMetadataRegistryTestData.categoryIdentifier,
            name: "Example Token",
            symbol: "EXAMPLE",
            decimals: 2,
            iconURL: try BitcoinCashMetadataRegistryTestData.registryIconLocation,
            lastUpdated: Date(timeIntervalSince1970: 1_704_067_200),
            source: .embedded
        )
        
        await store.upsert([try BitcoinCashMetadataRegistryTestData.categoryIdentifier: metadata])
        let snapshot = await store.snapshot()
        
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let decodedSnapshot = try JSONDecoder().decode(OpalBase.CashTokens.MetadataRepository.Snapshot.self, from: encodedSnapshot)
        
        let restoredStore = OpalBase.CashTokens.MetadataRepository()
        await restoredStore.applySnapshot(decodedSnapshot)
        
        let restoredMetadata = await restoredStore.fetchMetadata(
            for: try BitcoinCashMetadataRegistryTestData.categoryIdentifier
        )
        
        #expect(restoredMetadata == metadata)
    }

    @Test("applySnapshot removes unsafe metadata URLs")
    func applySnapshotRemovesUnsafeMetadataURLs() async throws {
        let store = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: try BitcoinCashMetadataRegistryTestData.categoryIdentifier,
            name: "Unsafe Token",
            symbol: "UNSAFE",
            decimals: 2,
            iconURL: URL(string: "http://example.com/icon.png")!,
            lastUpdated: Date(timeIntervalSince1970: 1_704_067_200),
            source: .dns(URL(string: "http://example.com/registry.json")!),
            webURL: URL(string: "javascript:alert(1)")!,
            registryURL: URL(string: "file:///tmp/registry.json")!
        )
        let snapshot = OpalBase.CashTokens.MetadataRepository.Snapshot(
            byCategory: [
                try BitcoinCashMetadataRegistryTestData.categoryIdentifier.hexForDisplay: metadata
            ]
        )

        await store.applySnapshot(snapshot)

        let restoredMetadata = try #require(
            await store.fetchMetadata(for: try BitcoinCashMetadataRegistryTestData.categoryIdentifier)
        )
        #expect(restoredMetadata.iconURL == nil)
        #expect(restoredMetadata.webURL == nil)
        #expect(restoredMetadata.registryURL == nil)
        #expect(restoredMetadata.source == .embedded)
    }

    @Test("applySnapshot removes hostless metadata URLs")
    func applySnapshotRemovesHostlessMetadataURLs() async throws {
        let store = OpalBase.CashTokens.MetadataRepository()
        let iconURL = try #require(URL(string: "https:example.com/icon.png"))
        let webURL = try #require(URL(string: "https:example.com/token"))
        let registryURL = try #require(URL(string: "https:example.com/registry.json"))
        let metadata = OpalBase.CashTokens.Metadata(
            category: try BitcoinCashMetadataRegistryTestData.categoryIdentifier,
            name: "Hostless Token",
            symbol: "HOSTLESS",
            decimals: 2,
            iconURL: iconURL,
            lastUpdated: Date(timeIntervalSince1970: 1_704_067_200),
            source: .dns(registryURL),
            webURL: webURL,
            registryURL: registryURL
        )
        let snapshot = OpalBase.CashTokens.MetadataRepository.Snapshot(
            byCategory: [
                try BitcoinCashMetadataRegistryTestData.categoryIdentifier.hexForDisplay: metadata
            ]
        )

        await store.applySnapshot(snapshot)

        let restoredMetadata = try #require(
            await store.fetchMetadata(for: try BitcoinCashMetadataRegistryTestData.categoryIdentifier)
        )
        #expect(restoredMetadata.iconURL == nil)
        #expect(restoredMetadata.webURL == nil)
        #expect(restoredMetadata.registryURL == nil)
        #expect(restoredMetadata.source == .embedded)
    }
}
