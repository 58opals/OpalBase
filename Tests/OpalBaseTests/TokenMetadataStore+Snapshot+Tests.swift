import Foundation
import Testing
@testable import OpalBase

@Suite("Token metadata store snapshots", .tags(.unit, .cashTokens))
struct TokenMetadataStoreSnapshotTests {
    @Test("roundtrips store snapshots with metadata")
    func roundtripStoreSnapshotsWithMetadata() async throws {
        let store = TokenMetadataStore()
        let metadata = TokenMetadata(
            category: BCMRFixtures.categoryIdentifier,
            name: "Example Token",
            symbol: "EXAMPLE",
            decimals: 2,
            iconURL: BCMRFixtures.registryIconLocation,
            lastUpdated: Date(timeIntervalSince1970: 1_704_067_200),
            source: .embedded
        )
        
        await store.upsert([BCMRFixtures.categoryIdentifier: metadata])
        let snapshot = await store.snapshot()
        
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let decodedSnapshot = try JSONDecoder().decode(TokenMetadataStore.Snapshot.self, from: encodedSnapshot)
        
        let restoredStore = TokenMetadataStore()
        await restoredStore.applySnapshot(decodedSnapshot)
        
        let restoredMetadata = await restoredStore.fetchMetadata(
            for: BCMRFixtures.categoryIdentifier
        )
        
        #expect(restoredMetadata == metadata)
    }
}
