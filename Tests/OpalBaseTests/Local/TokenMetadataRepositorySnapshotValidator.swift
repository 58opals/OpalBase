import Foundation
import Testing
@testable import OpalBase

@Suite("Token metadata store snapshots", .tags(.unit, .cashTokens))
struct TokenMetadataRepositorySnapshotValidator {
    @Test("roundtrips store snapshots with metadata")
    func roundtripStoreSnapshotsWithMetadata() async throws {
        let store = TokenMetadataRepository()
        let metadata = TokenMetadata(
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
        let decodedSnapshot = try JSONDecoder().decode(TokenMetadataRepository.Snapshot.self, from: encodedSnapshot)
        
        let restoredStore = TokenMetadataRepository()
        await restoredStore.applySnapshot(decodedSnapshot)
        
        let restoredMetadata = await restoredStore.fetchMetadata(
            for: BitcoinCashMetadataRegistryTestData.categoryIdentifier
        )
        
        #expect(restoredMetadata == metadata)
    }
}
