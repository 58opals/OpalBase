import Foundation
import Testing
@testable import OpalBase

@Suite("Bitcoin Cash Metadata Registry", .tags(.unit, .cashTokens))
struct BitcoinCashMetadataRegistryTests {
    @Test("parses publication output script")
    func parsePublicationOutputScript() throws {
        let script = BCMRFixtures.publicationScript
        #expect(script.hexadecimalString.hasPrefix("6a0442434d52"))
        
        let publication = try #require(
            BitcoinCashMetadataRegistries.parsePublicationOutput(lockingScript: script)
        )
        
        #expect(publication.sha256 == BCMRFixtures.publicationHash)
        #expect(
            publication.uris == [
                BCMRFixtures.publicationUniformResourceIdentifier
            ]
        )
    }
    
    @Test("verifies registry hash")
    func verifyRegistryHash() {
        let registryHash = SHA256.hash(BCMRFixtures.registryData)
        #expect(registryHash == BCMRFixtures.registryHash)
    }
    
    @Test("decodes registry and extracts token metadata")
    func decodeRegistryAndExtractTokenMetadata() throws {
        let registries = BCMRTestSupport.makeRegistries()
        let metadataByCategory = try registries.addEmbeddedRegistry(
            data: BCMRFixtures.registryData
        )
        
        let metadata = try #require(
            metadataByCategory[BCMRFixtures.categoryIdentifier]
        )
        
        #expect(metadata.name == "Example Token")
        #expect(metadata.symbol == "EXAMPLE")
        #expect(metadata.decimals == 2)
        #expect(metadata.iconURL == BCMRFixtures.registryIconLocation)
        #expect(metadata.source == .embedded)
        
        let expectedDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")
        #expect(metadata.lastUpdated == expectedDate)
    }
}
