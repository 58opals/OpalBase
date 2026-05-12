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
            category: BitcoinCashMetadataRegistryTestData.categoryIdentifier,
            name: "Example Token",
            symbol: "EXAMPLE",
            decimals: 2,
            iconURL: BitcoinCashMetadataRegistryTestData.registryIconLocation,
            lastUpdated: Date(timeIntervalSince1970: 1_704_067_200),
            source: .embedded
        )
        
        await store.upsert([BitcoinCashMetadataRegistryTestData.categoryIdentifier: metadata])
        let snapshot = await store.snapshot()
        
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let decodedSnapshot = try JSONDecoder().decode(OpalBase.CashTokens.MetadataRepository.Snapshot.self, from: encodedSnapshot)
        
        let restoredStore = OpalBase.CashTokens.MetadataRepository()
        await restoredStore.applySnapshot(decodedSnapshot)
        
        let restoredMetadata = await restoredStore.fetchMetadata(
            for: BitcoinCashMetadataRegistryTestData.categoryIdentifier
        )
        
        #expect(restoredMetadata == metadata)
    }

    @Test("applySnapshot removes unsafe metadata URLs")
    func applySnapshotRemovesUnsafeMetadataURLs() async throws {
        let store = OpalBase.CashTokens.MetadataRepository()
        let metadata = OpalBase.CashTokens.Metadata(
            category: BitcoinCashMetadataRegistryTestData.categoryIdentifier,
            name: "Unsafe Token",
            symbol: "UNSAFE",
            decimals: 2,
            iconURL: URL(string: "http://example.com/icon.png")!,
            lastUpdated: Date(timeIntervalSince1970: 1_704_067_200),
            source: .embedded,
            webURL: URL(string: "javascript:alert(1)")!,
            registryURL: URL(string: "file:///tmp/registry.json")!
        )
        let snapshot = OpalBase.CashTokens.MetadataRepository.Snapshot(
            byCategory: [
                BitcoinCashMetadataRegistryTestData.categoryIdentifier.hexForDisplay: metadata
            ]
        )

        await store.applySnapshot(snapshot)

        let restoredMetadata = try #require(
            await store.fetchMetadata(for: BitcoinCashMetadataRegistryTestData.categoryIdentifier)
        )
        #expect(restoredMetadata.iconURL == nil)
        #expect(restoredMetadata.webURL == nil)
        #expect(restoredMetadata.registryURL == nil)
    }
}
