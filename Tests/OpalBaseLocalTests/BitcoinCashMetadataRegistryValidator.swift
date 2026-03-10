// BitcoinCashMetadataRegistryValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Bitcoin Cash Metadata Registry", .tags(.unit, .cashTokens))
struct BitcoinCashMetadataRegistryValidator {
    @Test("parses publication output script")
    func parsePublicationOutputScript() throws {
        let script = BitcoinCashMetadataRegistryTestData.publicationScript
        #expect(script.hexadecimalString.hasPrefix("6a0442434d52"))
        
        let publication = try #require(
            OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(lockingScript: script)
        )
        
        #expect(publication.sha256 == BitcoinCashMetadataRegistryTestData.publicationHash)
        #expect(
            publication.uris == [
                BitcoinCashMetadataRegistryTestData.publicationUniformResourceIdentifier
            ]
        )
    }
    
    @Test("verifies registry hash")
    func verifyRegistryHash() {
        let registryHash = OpalCrypto.Hashing.computeSHA256(BitcoinCashMetadataRegistryTestData.registryData)
        #expect(registryHash == BitcoinCashMetadataRegistryTestData.registryHash)
    }
    
    @Test("decodes registry and extracts token metadata")
    func decodeRegistryAndExtractTokenMetadata() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let metadataByCategory = try registries.addEmbeddedRegistry(
            data: BitcoinCashMetadataRegistryTestData.registryData
        )
        
        let metadata = try #require(
            metadataByCategory[BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )
        
        #expect(metadata.name == "Example Token")
        #expect(metadata.symbol == "EXAMPLE")
        #expect(metadata.decimals == 2)
        #expect(metadata.iconURL == BitcoinCashMetadataRegistryTestData.registryIconLocation)
        #expect(metadata.source == .embedded)
        
        let expectedDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")
        #expect(metadata.lastUpdated == expectedDate)
    }
}
