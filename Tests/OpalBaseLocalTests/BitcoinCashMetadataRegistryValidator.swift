// BitcoinCashMetadataRegistryValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Bitcoin Cash Metadata Registry", .tags(.unit, .cashTokens), .serialized)
struct BitcoinCashMetadataRegistryValidator {
    @Test("parses publication output script")
    func parsePublicationOutputScript() throws {
        let script = try BitcoinCashMetadataRegistryTestData.publicationScript
        #expect(script.hexadecimalString.hasPrefix("6a0442434d52"))
        
        let publication = try #require(
            OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(lockingScript: script)
        )
        
        #expect(publication.sha256 == (try BitcoinCashMetadataRegistryTestData.publicationHash))
        #expect(
            publication.uris == [
                BitcoinCashMetadataRegistryTestData.publicationUniformResourceIdentifier
            ]
        )
    }

    @Test("parses sliced publication output script")
    func parseSlicedPublicationOutputScript() throws {
        let script = try BitcoinCashMetadataRegistryTestData.publicationScript
        let paddedScript = Data([0x00]) + script
        let slicedScript = paddedScript[paddedScript.index(after: paddedScript.startIndex)...]

        let publication = try #require(
            OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(lockingScript: slicedScript)
        )

        #expect(slicedScript.startIndex != 0)
        #expect(publication.sha256 == (try BitcoinCashMetadataRegistryTestData.publicationHash))
        #expect(
            publication.uris == [
                BitcoinCashMetadataRegistryTestData.publicationUniformResourceIdentifier
            ]
        )
    }

    @Test("registry fetch results normalize sliced bytes")
    func registryFetchResultsNormalizeSlicedBytes() throws {
        let bytes = Data("{\"version\":\"1\"}".utf8)
        let paddedBytes = Data([0x00]) + bytes
        let slicedBytes = paddedBytes[paddedBytes.index(after: paddedBytes.startIndex)...]

        let result = OpalBase.CashTokens.BCMR.Client.Fetcher.RegistryFetchResult(
            bytes: slicedBytes,
            finalURL: try #require(URL(string: "https://registry.example/metadata.json")),
            cacheExpiration: nil,
            permanentRedirectLocation: nil
        )

        #expect(slicedBytes.startIndex != 0)
        #expect(result.bytes == bytes)
        #expect(result.bytes.startIndex == 0)
    }

    @Test("publication initializers normalize sliced hash bytes")
    func publicationInitializersNormalizeSlicedHashBytes() throws {
        let hash = try BitcoinCashMetadataRegistryTestData.publicationHash
        let paddedHash = Data([0x00]) + hash
        let slicedHash = paddedHash[paddedHash.index(after: paddedHash.startIndex)...]

        let publication = OpalBase.CashTokens.BCMR.Client.Publication(
            sha256: slicedHash,
            uris: [BitcoinCashMetadataRegistryTestData.publicationUniformResourceIdentifier]
        )

        #expect(slicedHash.startIndex != 0)
        #expect(publication.sha256 == hash)
        #expect(publication.sha256.startIndex == 0)
    }

    @Test("rejects publication marker after leading script bytes")
    func rejectsPublicationMarkerAfterLeadingScriptBytes() throws {
        var script = Data([ScriptOperationCode._1.rawValue])
        script.append(try BitcoinCashMetadataRegistryTestData.publicationScript)

        let publication = OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(
            lockingScript: script
        )

        #expect(publication == nil)
    }
    
    @Test("rejects publication outputs without registry locations")
    func rejectsPublicationOutputsWithoutRegistryLocations() throws {
        let prefix = Data([0x42, 0x43, 0x4d, 0x52])
        var script = Data([0x6a])
        script.append(Data.push(prefix))
        script.append(Data.push(try BitcoinCashMetadataRegistryTestData.publicationHash))
        
        let publication = OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(
            lockingScript: script
        )
        
        #expect(publication == nil)
    }

    @Test("rejects publication outputs with blank registry locations")
    func rejectsPublicationOutputsWithBlankRegistryLocations() throws {
        let script = makePublicationScript(
            sha256: try BitcoinCashMetadataRegistryTestData.publicationHash,
            uris: [" \n"]
        )

        let publication = OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(
            lockingScript: script
        )

        #expect(publication == nil)
    }
    
    @Test("verifies registry hash")
    func verifyRegistryHash() throws {
        let registryHash = OpalCrypto.Hashing.sha256(BitcoinCashMetadataRegistryTestData.registryData)
        #expect(registryHash == (try BitcoinCashMetadataRegistryTestData.registryHash))
    }
    
    @Test("decodes registry and extracts token metadata")
    func decodeRegistryAndExtractTokenMetadata() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let metadataByCategory = try registries.addEmbeddedRegistry(
            data: BitcoinCashMetadataRegistryTestData.registryData
        )
        
        let metadata = try #require(
            metadataByCategory[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )
        
        #expect(metadata.name == "Example Token")
        #expect(metadata.symbol == "EXAMPLE")
        #expect(metadata.decimals == 2)
        #expect(metadata.iconURL == (try BitcoinCashMetadataRegistryTestData.registryIconLocation))
        #expect(metadata.description == "Example token description")
        #expect(metadata.webURL == nil)
        #expect(metadata.identity == "example.identity")
        #expect(metadata.authbase == nil)
        #expect(metadata.registryURL == nil)
        #expect(metadata.source == .embedded)
        
        let expectedDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")
        #expect(metadata.lastUpdated == expectedDate)
    }

    @Test("extracts token metadata without negative decimals")
    func extractTokenMetadataDropsNegativeDecimals() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let category = try makeCategoryIdentifier(byte: 0x12)
        let registry = makeRegistry(snapshots: [
            "2024-01-01T00:00:00Z": makeIdentitySnapshot(
                name: "Negative Decimals",
                category: category,
                symbol: "NEG",
                decimals: -1
            )
        ])

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[category]
        )

        #expect(metadata.decimals == nil)
    }

    @Test("extracts identity, authbase, web URL, and registry URL")
    func extractIdentityAuthbaseWebURLAndRegistryURL() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let identityHexadecimal = String(repeating: "11", count: 32)
        let identityAuthbase = OpalBase.Transaction.Hash(
            dataFromRPC: try Data(hexadecimalString: identityHexadecimal)
        )
        let webURL = try #require(URL(string: "https://example.com/token"))
        let registryURL = try #require(URL(string: "https://example.com/registry.json"))
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                identityHexadecimal: [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Rich Token",
                        description: "Rich token description",
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "RICH",
                            decimals: 8
                        ),
                        uris: [
                            "icon": try BitcoinCashMetadataRegistryTestData.registryIconLocation.absoluteString,
                            "web": webURL.absoluteString,
                            "registry": registryURL.absoluteString
                        ]
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.name == "Rich Token")
        #expect(metadata.symbol == "RICH")
        #expect(metadata.decimals == 8)
        #expect(metadata.description == "Rich token description")
        #expect(metadata.iconURL == (try BitcoinCashMetadataRegistryTestData.registryIconLocation))
        #expect(metadata.webURL == webURL)
        #expect(metadata.identity == identityHexadecimal)
        #expect(metadata.authbase == identityAuthbase)
        #expect(metadata.registryURL == registryURL)
    }

    @Test("metadata extraction keeps prefixed identity keys out of authbase")
    func metadataExtractionKeepsPrefixedIdentityKeysOutOfAuthbase() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let prefixedIdentity = "0x\(String(repeating: "11", count: 32))"
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                prefixedIdentity: [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Prefixed Identity Token",
                        description: nil,
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "PREFIX",
                            decimals: 0
                        ),
                        uris: nil
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.identity == prefixedIdentity)
        #expect(metadata.authbase == nil)
    }

    @Test("importRegistry rejects prefixed registry identities")
    func importRegistryRejectsPrefixedRegistryIdentities() async throws {
        let registryIdentity = "0x\(String(repeating: "11", count: 32))"
        let registryData = Data(
            #"{"version":"1","registryIdentity":"\#(registryIdentity)","identities":{}}"#.utf8
        )
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, registryData)
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            throw RegistryValidatorPlaceholderError.unused
        }
        let authchainResolver = OpalBase.CashTokens.BCMR.Client.AuthchainResolver(
            transactionReader: transactionReader,
            addressReader: makeUnusedAddressReader(),
            maxDepth: 0
        )
        let client = OpalBase.CashTokens.BCMR.Client(
            authchainResolver: authchainResolver,
            registryFetcher: .init(urlSession: session, maxBytes: 1_024)
        )

        let failedIdentity = try await captureInvalidRegistryIdentity {
            _ = try await client.importRegistry(from: "https://registry.example/registry.json")
        }
        #expect(failedIdentity == registryIdentity)
    }

    @Test("metadata extraction ignores relative URI values")
    func metadataExtractionIgnoresRelativeURIValues() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "example.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Relative URI Token",
                        description: nil,
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "REL",
                            decimals: 2
                        ),
                        uris: [
                            "icon": "icon.png",
                            "web": "/token",
                            "registry": "registry.json"
                        ]
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.iconURL == nil)
        #expect(metadata.webURL == nil)
        #expect(metadata.registryURL == nil)
    }

    @Test("metadata extraction ignores unsafe URI schemes")
    func metadataExtractionIgnoresUnsafeURISchemes() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "example.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Unsafe URI Token",
                        description: nil,
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "UNSAFE",
                            decimals: 2
                        ),
                        uris: [
                            "icon": "http://example.com/icon.png",
                            "web": "javascript:alert(1)",
                            "registry": "file:///tmp/registry.json"
                        ]
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.iconURL == nil)
        #expect(metadata.webURL == nil)
        #expect(metadata.registryURL == nil)
    }

    @Test("metadata extraction ignores hostless HTTPS URI values")
    func metadataExtractionIgnoresHostlessHTTPSURIValues() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "example.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Hostless URI Token",
                        description: nil,
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "HOSTLESS",
                            decimals: 2
                        ),
                        uris: [
                            "icon": "https:///icon.png",
                            "web": "https:///token",
                            "registry": "https:///registry.json"
                        ]
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.iconURL == nil)
        #expect(metadata.webURL == nil)
        #expect(metadata.registryURL == nil)
    }

    @Test("metadata extraction ignores URI values with embedded credentials")
    func metadataExtractionIgnoresURIValuesWithEmbeddedCredentials() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "example.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Credential URI Token",
                        description: nil,
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "CRED",
                            decimals: 2
                        ),
                        uris: [
                            "icon": "https://user:secret@example.com/icon.png",
                            "web": "https://user@example.com/token",
                            "registry": "ipfs://user@bafybeigdyrzt/registry.json"
                        ]
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.iconURL == nil)
        #expect(metadata.webURL == nil)
        #expect(metadata.registryURL == nil)
    }

    @Test("metadata extraction ignores empty IPFS URI values")
    func metadataExtractionIgnoresEmptyInterPlanetaryFileSystemURIValues() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "example.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Empty IPFS URI Token",
                        description: nil,
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "EMPTYIPFS",
                            decimals: 2
                        ),
                        uris: [
                            "icon": "ipfs:",
                            "web": "ipfs://",
                            "registry": "ipfs://?version=1"
                        ]
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.iconURL == nil)
        #expect(metadata.webURL == nil)
        #expect(metadata.registryURL == nil)
    }

    @Test("latest metadata snapshot prefers dated keys over unparsable keys")
    func latestMetadataSnapshotPrefersDatedKeysOverUnparsableKeys() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "example.identity": [
                    "2024-01-01T00:00:00Z": .init(
                        name: "Dated Token",
                        description: nil,
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "DATED",
                            decimals: 2
                        ),
                        uris: nil
                    ),
                    "zzzz": .init(
                        name: "Undated Token",
                        description: nil,
                        token: .init(
                            category: BitcoinCashMetadataRegistryTestData.categoryHexadecimal,
                            symbol: "UNDATED",
                            decimals: 0
                        ),
                        uris: nil
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[try BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.name == "Dated Token")
        #expect(metadata.symbol == "DATED")
        #expect(metadata.decimals == 2)
        #expect(metadata.lastUpdated == ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z"))
    }

    @Test("current metadata ignores future snapshots when a reached snapshot exists")
    func currentMetadataIgnoresFutureSnapshotsWhenReachedSnapshotExists() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let currentCategory = try makeCategoryIdentifier(byte: 0x10)
        let futureCategory = try makeCategoryIdentifier(byte: 0x20)
        let registry = makeRegistry(
            snapshots: [
                "2024-01-01T00:00:00Z": makeIdentitySnapshot(
                    name: "Current Token",
                    category: currentCategory,
                    symbol: "CURRENT"
                ),
                "2030-01-01T00:00:00Z": makeIdentitySnapshot(
                    name: "Future Token",
                    category: futureCategory,
                    symbol: "FUTURE"
                )
            ]
        )

        let metadataByCategory = registries.extractTokenMetadata(
            from: registry,
            asOf: try makeDate("2025-01-01T00:00:00Z")
        )

        #expect(metadataByCategory[currentCategory]?.name == "Current Token")
        #expect(metadataByCategory[futureCategory] == nil)
    }

    @Test("future-only metadata uses the oldest future snapshot")
    func futureOnlyMetadataUsesOldestFutureSnapshot() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let firstFutureCategory = try makeCategoryIdentifier(byte: 0x30)
        let secondFutureCategory = try makeCategoryIdentifier(byte: 0x40)
        let registry = makeRegistry(
            snapshots: [
                "2031-01-01T00:00:00Z": makeIdentitySnapshot(
                    name: "Second Future Token",
                    category: secondFutureCategory,
                    symbol: "SECOND"
                ),
                "2030-01-01T00:00:00Z": makeIdentitySnapshot(
                    name: "First Future Token",
                    category: firstFutureCategory,
                    symbol: "FIRST"
                )
            ]
        )

        let metadataByCategory = registries.extractTokenMetadata(
            from: registry,
            asOf: try makeDate("2025-01-01T00:00:00Z")
        )

        #expect(metadataByCategory[firstFutureCategory]?.name == "First Future Token")
        #expect(metadataByCategory[secondFutureCategory] == nil)
    }

    @Test("historical token categories remain mapped after migrations")
    func historicalTokenCategoriesRemainMappedAfterMigrations() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let historicalCategory = try makeCategoryIdentifier(byte: 0x50)
        let currentCategory = try makeCategoryIdentifier(byte: 0x60)
        let registry = makeRegistry(
            snapshots: [
                "2023-01-01T00:00:00Z": makeIdentitySnapshot(
                    name: "Historical Token",
                    category: historicalCategory,
                    symbol: "TOKEN-OLD"
                ),
                "2024-01-01T00:00:00Z": makeIdentitySnapshot(
                    name: "Current Token",
                    description: "Current description",
                    migrated: "2024-06-01T00:00:00Z",
                    category: currentCategory,
                    symbol: "TOKEN"
                )
            ]
        )

        let metadataByCategory = registries.extractTokenMetadata(
            from: registry,
            asOf: try makeDate("2025-01-01T00:00:00Z")
        )

        #expect(metadataByCategory[currentCategory]?.name == "Current Token")
        #expect(metadataByCategory[currentCategory]?.symbol == "TOKEN")
        #expect(metadataByCategory[currentCategory]?.description == "Current description")
        #expect(metadataByCategory[historicalCategory]?.name == "Historical Token")
        #expect(metadataByCategory[historicalCategory]?.symbol == "TOKEN-OLD")
    }

    @Test("current metadata ignores snapshots with future migration dates")
    func currentMetadataIgnoresSnapshotsWithFutureMigrationDates() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let currentCategory = try makeCategoryIdentifier(byte: 0x53)
        let futureMigrationCategory = try makeCategoryIdentifier(byte: 0x54)
        let registry = makeRegistry(
            snapshots: [
                "2024-01-01T00:00:00Z": makeIdentitySnapshot(
                    name: "Current Token",
                    category: currentCategory,
                    symbol: "CURRENT"
                ),
                "2024-06-01T00:00:00Z": makeIdentitySnapshot(
                    name: "Future Migration Token",
                    migrated: "2026-01-01T00:00:00Z",
                    category: futureMigrationCategory,
                    symbol: "FUTURE"
                )
            ]
        )

        let metadataByCategory = registries.extractTokenMetadata(
            from: registry,
            asOf: try makeDate("2025-01-01T00:00:00Z")
        )

        #expect(metadataByCategory[currentCategory]?.name == "Current Token")
        #expect(metadataByCategory[futureMigrationCategory] == nil)
    }

    @Test("duplicate category metadata prefers the newest current snapshot")
    func duplicateCategoryMetadataPrefersNewestCurrentSnapshot() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let category = try makeCategoryIdentifier(byte: 0x70)
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "older.identity": [
                    "2024-01-01T00:00:00Z": makeIdentitySnapshot(
                        name: "Older Token",
                        category: category,
                        symbol: "OLDER"
                    )
                ],
                "newer.identity": [
                    "2025-01-01T00:00:00Z": makeIdentitySnapshot(
                        name: "Newer Token",
                        category: category,
                        symbol: "NEWER"
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(
                from: registry,
                asOf: try makeDate("2026-01-01T00:00:00Z")
            )[category]
        )

        #expect(metadata.name == "Newer Token")
        #expect(metadata.symbol == "NEWER")
    }
    
    @Test("duplicate category metadata uses migrated dates for freshness")
    func duplicateCategoryMetadataUsesMigratedDatesForFreshness() throws {
        let registries = BitcoinCashMetadataRegistryTestClient.makeRegistries()
        let category = try makeCategoryIdentifier(byte: 0x71)
        let migratedDate = try makeDate("2026-01-01T00:00:00Z")
        let registry = OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: [
                "identity-a": [
                    "2024-01-01T00:00:00Z": makeIdentitySnapshot(
                        name: "Migrated Token",
                        migrated: "2026-01-01T00:00:00Z",
                        category: category,
                        symbol: "MIGRATED"
                    )
                ],
                "identity-b": [
                    "2025-01-01T00:00:00Z": makeIdentitySnapshot(
                        name: "Stale Token",
                        category: category,
                        symbol: "STALE"
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(
                from: registry,
                asOf: try makeDate("2027-01-01T00:00:00Z")
            )[category]
        )

        #expect(metadata.name == "Migrated Token")
        #expect(metadata.symbol == "MIGRATED")
        #expect(metadata.lastUpdated == migratedDate)
    }
    
    @Test("authchain transaction decode rejects invalid payloads", arguments: AuthchainInvalidPayloadCase.allCases)
    func authchainTransactionDecodeRejectsInvalidPayloads(
        _ invalidPayloadCase: AuthchainInvalidPayloadCase
    ) throws {
        let transactionHash = invalidPayloadCase.transactionHash
        let rawTransactionData = try invalidPayloadCase.makeRawTransactionData()

        do {
            _ = try OpalBase.CashTokens.BCMR.Client.AuthchainResolver.decodeTransaction(
                rawTransactionData,
                transactionHash: transactionHash
            )
            Issue.record("Expected authchain decode to reject \(invalidPayloadCase)")
        } catch let error as OpalBase.CashTokens.BCMR.Client.AuthchainResolver.Error {
            guard case .transactionDecodingFailed(let failedHash, let underlying) = error else {
                Issue.record("Expected transactionDecodingFailed, got \(error)")
                return
            }
            #expect(failedHash == transactionHash)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == invalidPayloadCase.expectedReason)
            #expect(networkError.message == invalidPayloadCase.expectedMessage)
            if invalidPayloadCase.requiresHashMetadata {
                #expect(networkError.metadata["expected"] == transactionHash.reverseOrder.hexadecimalString)
                #expect(networkError.metadata["actual"] == OpalBase.Transaction.Hash(
                    naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
                ).reverseOrder.hexadecimalString)
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test(
        "chain registry resolution rejects invalid authhead payloads",
        arguments: AuthchainInvalidPayloadCase.allCases
    )
    func chainRegistryResolutionRejectsInvalidAuthheadPayloads(
        _ invalidPayloadCase: AuthchainInvalidPayloadCase
    ) async throws {
        let registryURI = "https://registry.example/registry.json"
        let publicationScript = makePublicationScript(
            sha256: try BitcoinCashMetadataRegistryTestData.registryHash,
            uris: [registryURI]
        )
        let rawTransactionData = try BitcoinCashMetadataRegistryValidator.makeAuthchainTransactionData(lockingScript: publicationScript)
        let authbase = OpalBase.Transaction.Hash(naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData))
        let invalidAuthheadData: Data
        switch invalidPayloadCase {
        case .trailingBytes:
            invalidAuthheadData = rawTransactionData + Data([0x00])
        case .mismatchedHash:
            invalidAuthheadData = try BitcoinCashMetadataRegistryValidator.makeAuthchainTransactionData()
        }
        let rawTransactions = RawTransactionSequence([
            rawTransactionData,
            invalidAuthheadData
        ])
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            try rawTransactions.next()
        }
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, BitcoinCashMetadataRegistryTestData.registryData)
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let client = makeChainRegistryTestClient(
            transactionReader: transactionReader,
            session: session
        )

        do {
            _ = try await client.resolveChainRegistry(authbase: authbase)
            Issue.record("Expected chain registry resolution to reject \(invalidPayloadCase)")
        } catch let error as OpalBase.CashTokens.BCMR.Client.AuthchainResolver.Error {
            guard case .transactionDecodingFailed(let failedHash, let underlying) = error else {
                Issue.record("Expected transactionDecodingFailed, got \(error)")
                return
            }
            #expect(failedHash == authbase)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == invalidPayloadCase.expectedReason)
            #expect(networkError.message == invalidPayloadCase.expectedMessage)
            if invalidPayloadCase.requiresHashMetadata {
                #expect(networkError.metadata["expected"] == authbase.reverseOrder.hexadecimalString)
                #expect(networkError.metadata["actual"] == OpalBase.Transaction.Hash(
                    naturalOrder: OpalCryptoAdapter.hash256(invalidAuthheadData)
                ).reverseOrder.hexadecimalString)
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("chain registry resolution falls back across publication URIs")
    func chainRegistryResolutionFallsBackAcrossPublicationURIs() async throws {
        let primaryURI = "https://registry.example/missing.json"
        let fallbackURI = "https://registry.example/registry.json"
        let publicationScript = makePublicationScript(
            sha256: try BitcoinCashMetadataRegistryTestData.registryHash,
            uris: [primaryURI, fallbackURI]
        )
        let rawTransactionData = try BitcoinCashMetadataRegistryValidator.makeAuthchainTransactionData(lockingScript: publicationScript)
        let authbase = OpalBase.Transaction.Hash(naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData))
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            rawTransactionData
        }
        let (session, requestedURLs) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            if url.path == "/registry.json" {
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
                return (response, BitcoinCashMetadataRegistryTestData.registryData)
            }
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let client = makeChainRegistryTestClient(
            transactionReader: transactionReader,
            session: session
        )

        let resolved = try await client.resolveChainRegistry(authbase: authbase)

        #expect(resolved.publication.uris == [primaryURI, fallbackURI])
        #expect(resolved.registry.version == "1")
        #expect(requestedURLs.values.map(\.absoluteString) == [primaryURI, fallbackURI])
    }

    @Test("chain registry resolution falls back after invalid registry hash")
    func chainRegistryResolutionFallsBackAfterInvalidRegistryHash() async throws {
        let primaryURI = "https://registry.example/wrong.json"
        let fallbackURI = "https://registry.example/registry.json"
        let publicationScript = makePublicationScript(
            sha256: try BitcoinCashMetadataRegistryTestData.registryHash,
            uris: [primaryURI, fallbackURI]
        )
        let rawTransactionData = try BitcoinCashMetadataRegistryValidator.makeAuthchainTransactionData(lockingScript: publicationScript)
        let authbase = OpalBase.Transaction.Hash(naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData))
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            rawTransactionData
        }
        let (session, requestedURLs) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            if url.path == "/wrong.json" {
                return (response, Data("{\"version\":\"wrong\"}".utf8))
            }
            return (response, BitcoinCashMetadataRegistryTestData.registryData)
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let client = makeChainRegistryTestClient(
            transactionReader: transactionReader,
            session: session
        )

        let resolved = try await client.resolveChainRegistry(authbase: authbase)

        #expect(resolved.registry.version == "1")
        #expect(requestedURLs.values.map(\.absoluteString) == [primaryURI, fallbackURI])
    }

    @Test("chain registry resolution propagates registry fetch cancellation")
    func chainRegistryResolutionPropagatesRegistryFetchCancellation() async throws {
        let primaryURI = "https://registry.example/cancel.json"
        let fallbackURI = "https://registry.example/registry.json"
        let publicationScript = makePublicationScript(
            sha256: try BitcoinCashMetadataRegistryTestData.registryHash,
            uris: [primaryURI, fallbackURI]
        )
        let rawTransactionData = try BitcoinCashMetadataRegistryValidator.makeAuthchainTransactionData(lockingScript: publicationScript)
        let authbase = OpalBase.Transaction.Hash(naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData))
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            rawTransactionData
        }
        let (session, requestedURLs) = makeRegistryTestSession { _ in
            throw CancellationError()
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let client = makeChainRegistryTestClient(
            transactionReader: transactionReader,
            session: session
        )

        await #expect(throws: CancellationError.self) {
            _ = try await client.resolveChainRegistry(authbase: authbase)
        }
        #expect(requestedURLs.values.map(\.absoluteString) == [primaryURI])
    }

    @Test("registry fetcher resolves DNS and publication identifiers")
    func registryFetcherResolvesDNSAndPublicationIdentifiers() async throws {
        let (session, requestedURLs) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("{}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        _ = try await fetcher.fetchRegistry(from: "otr.cash")
        _ = try await fetcher.fetchRegistry(from: "example.com")
        _ = try await fetcher.fetchRegistry(from: "example.com:8443/registry.json")
        _ = try await fetcher.fetchRegistry(from: "https://example.com")
        _ = try await fetcher.fetchRegistry(from: "https://example.com/")
        _ = try await fetcher.fetchRegistry(from: "https://example.com/registry.json")

        #expect(requestedURLs.values.map(\.absoluteString) == [
            "https://otr.cash/.well-known/bitcoin-cash-metadata-registry.json",
            "https://example.com/.well-known/bitcoin-cash-metadata-registry.json",
            "https://example.com:8443/registry.json",
            "https://example.com/.well-known/bitcoin-cash-metadata-registry.json",
            "https://example.com/.well-known/bitcoin-cash-metadata-registry.json",
            "https://example.com/registry.json"
        ])
    }

    @Test("registry fetcher propagates cancellation")
    func registryFetcherPropagatesCancellation() async throws {
        let registryURI = "https://registry.example/registry.json"
        let (session, requestedURLs) = makeRegistryTestSession { _ in
            throw CancellationError()
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        await #expect(throws: CancellationError.self) {
            _ = try await fetcher.fetchRegistryBytes(
                from: registryURI
            )
        }
        #expect(requestedURLs.values.map(\.absoluteString) == [registryURI])
    }

    @Test("registry fetcher resolves IPFS through an HTTPS gateway")
    func registryFetcherResolvesInterPlanetaryFileSystemThroughHTTPSGateway() async throws {
        let (session, requestedURLs) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("{}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let gateway = try #require(URL(string: "https://gateway.example/base"))
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            ipfsGateway: gateway,
            maxBytes: 1_024
        )

        _ = try await fetcher.fetchRegistry(from: "ipfs://bafybeigdyrzt/path?version=1")

        #expect(requestedURLs.values.map(\.absoluteString) == [
            "https://gateway.example/base/ipfs/bafybeigdyrzt/path?version=1"
        ])
    }

    @Test("registry fetcher rejects IPFS without a gateway")
    func registryFetcherRejectsInterPlanetaryFileSystemWithoutGateway() async throws {
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(maxBytes: 1_024)
        var capturedError: OpalBase.CashTokens.BCMR.Client.Fetcher.Error?

        do {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt")
            Issue.record("Expected missingInterPlanetaryFileSystemGateway.")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            capturedError = error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let error = try #require(capturedError)
        switch error {
        case .missingInterPlanetaryFileSystemGateway:
            break
        default:
            Issue.record("Expected missingInterPlanetaryFileSystemGateway, got \(error).")
        }
    }
    
    @Test("registry fetcher rejects insecure IPFS gateways before fetching")
    func registryFetcherRejectsInsecureInterPlanetaryFileSystemGateways() async throws {
        let gateway = try #require(URL(string: "http://gateway.example"))
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: gateway,
            maxBytes: 1_024
        )
        var capturedError: OpalBase.CashTokens.BCMR.Client.Fetcher.Error?
        
        do {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt")
            Issue.record("Expected insecure IPFS gateway to be rejected before fetching")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            capturedError = error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let error = try #require(capturedError)
        switch error {
        case .invalidInterPlanetaryFileSystemGateway(gateway):
            break
        default:
            Issue.record("Expected invalidInterPlanetaryFileSystemGateway, got \(error)")
        }
    }

    @Test("registry fetcher rejects resource identifiers with embedded credentials")
    func registryFetcherRejectsResourceIdentifiersWithEmbeddedCredentials() async throws {
        let gateway = try #require(URL(string: "https://gateway.example"))
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: gateway,
            maxBytes: 1_024
        )

        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "https://user:secret@registry.example/metadata.json")
        }

        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://user@bafybeigdyrzt/metadata.json")
        }
    }

    @Test("registry fetcher rejects HTTPS locations with invalid ports")
    func registryFetcherRejectsHypertextTransferProtocolSecureLocationsWithInvalidPorts() async throws {
        let gateway = try #require(URL(string: "https://gateway.example:0"))
        let invalidGatewayFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: gateway,
            maxBytes: 1_024
        )
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await invalidGatewayFetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt/metadata.json")
        }

        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(maxBytes: 1_024)
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "https://registry.example:65536/metadata.json")
        }
    }

    @Test("registry fetcher rejects HTTPS traversal authorities")
    func registryFetcherRejectsHypertextTransferProtocolSecureTraversalAuthorities() async throws {
        let invalidGateway = try #require(URL(string: "https://./base"))
        let invalidGatewayFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: invalidGateway,
            maxBytes: 1_024
        )
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await invalidGatewayFetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt/metadata.json")
        }

        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(maxBytes: 1_024)
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "https://../metadata.json")
        }
    }

    @Test("registry fetcher rejects malformed HTTPS IP literals")
    func registryFetcherRejectsMalformedHypertextTransferProtocolSecureInternetProtocolLiterals() async throws {
        let invalidGatewayIPv6Literal = try #require(URL(string: "https://[::::]/base"))
        let invalidGatewayIPv6LiteralFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: invalidGatewayIPv6Literal,
            maxBytes: 1_024
        )
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await invalidGatewayIPv6LiteralFetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt/metadata.json")
        }

        let invalidGatewayIPv4Literal = try #require(URL(string: "https://999.999.999.999/base"))
        let invalidGatewayIPv4LiteralFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: invalidGatewayIPv4Literal,
            maxBytes: 1_024
        )
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await invalidGatewayIPv4LiteralFetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt/metadata.json")
        }

        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(maxBytes: 1_024)
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "https://[::::]/metadata.json")
        }
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "https://999.999.999.999/metadata.json")
        }
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "https://999.999.999.999./metadata.json")
        }
        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "https://999.999.999.999../metadata.json")
        }
    }

    @Test(
        "registry fetcher rejects HTTPS path traversal components",
        arguments: [
            "https://registry.example/../metadata.json",
            "https://registry.example/..\\metadata.json",
            "https://registry.example/%2e%2e/metadata.json",
            "https://registry.example/%252e%252e/metadata.json",
            "https://registry.example/%252e%252e%252fmetadata.json"
        ]
    )
    func registryFetcherRejectsHypertextTransferProtocolSecurePathTraversalComponents(
        invalidResourceIdentifier: String
    ) async throws {
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(maxBytes: 1_024)

        do {
            _ = try await fetcher.fetchRegistryBytes(from: invalidResourceIdentifier)
            Issue.record("Expected invalidResourceIdentifier for \(invalidResourceIdentifier).")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            switch error {
            case .invalidResourceIdentifier(let resourceIdentifier)
                where resourceIdentifier == invalidResourceIdentifier:
                break
            default:
                Issue.record("Expected invalidResourceIdentifier for \(invalidResourceIdentifier), got \(error).")
            }
        } catch {
            Issue.record("Unexpected error for \(invalidResourceIdentifier): \(error)")
        }
    }

    @Test("registry fetcher rejects IPFS gateways with embedded credentials")
    func registryFetcherRejectsInterPlanetaryFileSystemGatewaysWithEmbeddedCredentials() async throws {
        let gateway = try #require(URL(string: "https://user:secret@gateway.example"))
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: gateway,
            maxBytes: 1_024
        )
        var capturedError: OpalBase.CashTokens.BCMR.Client.Fetcher.Error?

        do {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt")
            Issue.record("Expected credentialed IPFS gateway to be rejected before fetching")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            capturedError = error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let error = try #require(capturedError)
        switch error {
        case .invalidInterPlanetaryFileSystemGateway(gateway):
            break
        default:
            Issue.record("Expected invalidInterPlanetaryFileSystemGateway, got \(error)")
        }
    }

    @Test("registry fetcher rejects IPFS path traversal components")
    func registryFetcherRejectsInterPlanetaryFileSystemPathTraversalComponents() async throws {
        let gateway = try #require(URL(string: "https://gateway.example/base"))
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: gateway,
            maxBytes: 1_024
        )

        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt/../registry.json")
        }

        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://../registry.json")
        }

        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt/%252e%252e/registry.json")
        }
    }

    @Test("registry fetcher rejects IPFS gateways with path traversal components")
    func registryFetcherRejectsInterPlanetaryFileSystemGatewaysWithPathTraversalComponents() async throws {
        let gateway = try #require(URL(string: "https://gateway.example/base/.."))
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: gateway,
            maxBytes: 1_024
        )

        await #expect(throws: OpalBase.CashTokens.BCMR.Client.Fetcher.Error.self) {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt")
        }
    }

    @Test("registry fetcher enforces maximum byte limits")
    func registryFetcherEnforcesMaximumByteLimits() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data(repeating: 0x41, count: 5))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 4
        )
        var capturedError: OpalBase.CashTokens.BCMR.Client.Fetcher.Error?

        do {
            _ = try await fetcher.fetchRegistryBytes(from: "https://registry.example/metadata.json")
            Issue.record("Expected responseTooLarge.")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            capturedError = error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let error = try #require(capturedError)
        switch error {
        case .responseTooLarge(limit: 4, actual: 5):
            break
        default:
            Issue.record("Expected responseTooLarge(limit: 4, actual: 5), got \(error).")
        }
    }

    @Test("registry fetcher follows temporary redirects and returns cache expiry")
    func registryFetcherFollowsTemporaryRedirectsAndReturnsCacheExpiry() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            if url.path == "/start" {
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": "/temporary"]
                ))
                return (response, Data())
            }

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Cache-Control": "public, max-age=60"]
            ))
            return (response, Data("{\"version\":\"1\"}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        let beforeFetch = Date()
        let result = try await fetcher.fetchRegistry(from: "https://registry.example/start")

        #expect(result.bytes == Data("{\"version\":\"1\"}".utf8))
        #expect(result.finalURL.absoluteString == "https://registry.example/temporary")
        #expect(result.permanentRedirectLocation == nil)
        #expect(result.cacheExpiration ?? .distantPast > beforeFetch)
    }

    @Test("registry fetcher parses max-age with optional whitespace")
    func registryFetcherParsesMaxAgeWithOptionalWhitespace() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Cache-Control": "public, max-age = 60"]
            ))
            return (response, Data("{}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        let beforeFetch = Date()
        let result = try await fetcher.fetchRegistry(from: "https://registry.example/metadata.json")

        #expect(result.cacheExpiration ?? .distantPast > beforeFetch)
    }

    @Test(
        "registry fetcher ignores non-finite max-age values",
        arguments: ["inf", "infinity", "1e309"]
    )
    func registryFetcherIgnoresNonFiniteMaxAge(cacheControlMaxAge: String) async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Cache-Control": "public, max-age=\(cacheControlMaxAge)"]
            ))
            return (response, Data("{}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        let result = try await fetcher.fetchRegistry(from: "https://registry.example/metadata.json")

        #expect(result.cacheExpiration == nil)
    }

    @Test(
        "registry fetcher ignores non-delta-seconds max-age values",
        arguments: ["1.5", "1e2", "+60", "-1", ""]
    )
    func registryFetcherIgnoresNonDeltaSecondsMaxAge(cacheControlMaxAge: String) async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Cache-Control": "public, max-age=\(cacheControlMaxAge)"]
            ))
            return (response, Data("{}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        let result = try await fetcher.fetchRegistry(from: "https://registry.example/metadata.json")

        #expect(result.cacheExpiration == nil)
    }

    @Test("registry fetcher follows temporary preserve-method redirects")
    func registryFetcherFollowsTemporaryPreserveMethodRedirects() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            if url.path == "/start" {
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 307,
                    httpVersion: nil,
                    headerFields: ["Location": "https://registry.example/temporary"]
                ))
                return (response, Data())
            }
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("{\"version\":\"1\"}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        let result = try await fetcher.fetchRegistry(from: "https://registry.example/start")

        #expect(result.bytes == Data("{\"version\":\"1\"}".utf8))
        #expect(result.finalURL.absoluteString == "https://registry.example/temporary")
        #expect(result.permanentRedirectLocation == nil)
    }

    @Test(
        "registry fetcher does not return cache expiry for revalidation directives",
        arguments: [
            "no-store, max-age=60",
            "no-cache, max-age=60",
            #"no-cache="Set-Cookie", max-age=60"#
        ]
    )
    func registryFetcherDoesNotReturnCacheExpiryForRevalidationDirectives(cacheControl: String) async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Cache-Control": cacheControl]
            ))
            return (response, Data("{}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        let result = try await fetcher.fetchRegistry(from: "https://registry.example/metadata.json")

        #expect(result.cacheExpiration == nil)
    }

    @Test("registry fetcher follows permanent redirects and returns the permanent location")
    func registryFetcherFollowsPermanentRedirectsAndReturnsPermanentLocation() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            if url.path == "/start" {
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 301,
                    httpVersion: nil,
                    headerFields: ["Location": "https://registry.example/permanent"]
                ))
                return (response, Data())
            }

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("{\"version\":\"1\"}".utf8))
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        let result = try await fetcher.fetchRegistry(from: "https://registry.example/start")

        #expect(result.finalURL.absoluteString == "https://registry.example/permanent")
        #expect(result.permanentRedirectLocation?.absoluteString == "https://registry.example/permanent")
    }

    @Test("registry fetcher rejects redirects to unsupported schemes")
    func registryFetcherRejectsRedirectsToUnsupportedSchemes() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "http://registry.example/metadata.json"]
            ))
            return (response, Data())
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }

        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        var capturedError: OpalBase.CashTokens.BCMR.Client.Fetcher.Error?
        do {
            _ = try await fetcher.fetchRegistryBytes(
                from: "https://registry.example/metadata.json"
            )
            Issue.record("Expected unsupportedScheme for HTTP redirect.")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            capturedError = error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let error = try #require(capturedError)
        switch error {
        case .unsupportedScheme("http"):
            break
        default:
            Issue.record("Expected unsupportedScheme(\"http\"), got \(error).")
        }
    }

    @Test("registry fetcher rejects redirects without a host")
    func registryFetcherRejectsRedirectsWithoutHost() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "https:///metadata.json"]
            ))
            return (response, Data())
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }

        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        var capturedError: OpalBase.CashTokens.BCMR.Client.Fetcher.Error?
        do {
            _ = try await fetcher.fetchRegistryBytes(
                from: "https://registry.example/metadata.json"
            )
            Issue.record("Expected invalidResourceIdentifier for hostless HTTPS redirect.")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            capturedError = error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let error = try #require(capturedError)
        switch error {
        case .invalidResourceIdentifier("https:///metadata.json"):
            break
        default:
            Issue.record("Expected invalidResourceIdentifier for hostless HTTPS redirect, got \(error).")
        }
    }

    @Test("registry fetcher rejects redirects with path traversal components")
    func registryFetcherRejectsRedirectsWithPathTraversalComponents() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "../metadata.json"]
            ))
            return (response, Data())
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }

        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )

        var capturedError: OpalBase.CashTokens.BCMR.Client.Fetcher.Error?
        do {
            _ = try await fetcher.fetchRegistryBytes(
                from: "https://registry.example/path/metadata.json"
            )
            Issue.record("Expected invalidResourceIdentifier for path traversal redirect.")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            capturedError = error
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let error = try #require(capturedError)
        switch error {
        case .invalidResourceIdentifier("../metadata.json"):
            break
        default:
            Issue.record("Expected invalidResourceIdentifier for path traversal redirect, got \(error).")
        }
    }

    enum AuthchainInvalidPayloadCase: CaseIterable, Sendable {
        case trailingBytes
        case mismatchedHash

        var transactionHash: OpalBase.Transaction.Hash {
            switch self {
            case .trailingBytes:
                return OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x44, count: 32))
            case .mismatchedHash:
                return OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x45, count: 32))
            }
        }

        var expectedReason: OpalBase.Network.Error.Reason {
            switch self {
            case .trailingBytes:
                return .decoding
            case .mismatchedHash:
                return .protocolViolation
            }
        }

        var expectedMessage: String {
            switch self {
            case .trailingBytes:
                return "Transaction payload has trailing bytes"
            case .mismatchedHash:
                return "Transaction payload hash mismatch"
            }
        }

        var requiresHashMetadata: Bool {
            self == .mismatchedHash
        }

        func makeRawTransactionData() throws -> Data {
            switch self {
            case .trailingBytes:
                return try BitcoinCashMetadataRegistryValidator.makeAuthchainTransactionData() + Data([0x00])
            case .mismatchedHash:
                return try BitcoinCashMetadataRegistryValidator.makeAuthchainTransactionData()
            }
        }
    }

    private func makeRegistry(
        snapshots: [String: OpalBase.CashTokens.BCMR.Client.IdentitySnapshot]
    ) -> OpalBase.CashTokens.BCMR.Client.Registry {
        OpalBase.CashTokens.BCMR.Client.Registry(
            version: "1",
            registryIdentity: nil,
            identities: ["example.identity": snapshots]
        )
    }

    private func makeIdentitySnapshot(
        name: String,
        description: String? = nil,
        migrated: String? = nil,
        category: OpalBase.CashTokens.CategoryID,
        symbol: String,
        decimals: Int = 2
    ) -> OpalBase.CashTokens.BCMR.Client.IdentitySnapshot {
        .init(
            name: name,
            description: description,
            migrated: migrated,
            token: .init(
                category: category.hexForDisplay,
                symbol: symbol,
                decimals: decimals
            ),
            uris: nil
        )
    }

    private func makeCategoryIdentifier(byte: UInt8) throws -> OpalBase.CashTokens.CategoryID {
        try OpalBase.CashTokens.CategoryID(
            hexFromRPC: Data(repeating: byte, count: 32).hexadecimalString
        )
    }

    private func makeDate(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    private func makePublicationScript(sha256: Data, uris: [String]) -> Data {
        let prefix = Data([0x42, 0x43, 0x4d, 0x52])
        var script = Data([0x6a])
        script.append(Data.push(prefix))
        script.append(Data.push(sha256))
        for uri in uris {
            script.append(Data.push(Data(uri.utf8)))
        }
        return script
    }

    private static func makeAuthchainTransactionData(
        lockingScript: Data = Data([ScriptOperationCode._1.rawValue])
    ) throws -> Data {
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(value: 0, lockingScript: lockingScript)
        return try OpalBase.Transaction(
            version: 1,
            inputs: [input],
            outputs: [output],
            lockTime: 0
        ).encode()
    }

    private func captureInvalidRegistryIdentity(
        _ operation: () async throws -> Void
    ) async throws -> String {
        let error = try await captureRegistryClientError(operation)
        guard case .invalidRegistryIdentity(let failedIdentity, _) = error else {
            throw RegistryClientErrorCaptureFailure.unexpectedClientError(String(describing: error))
        }
        return failedIdentity
    }

    private func captureRegistryClientError(
        _ operation: () async throws -> Void
    ) async throws -> OpalBase.CashTokens.BCMR.Client.Error {
        do {
            try await operation()
        } catch let error as OpalBase.CashTokens.BCMR.Client.Error {
            return error
        } catch {
            throw RegistryClientErrorCaptureFailure.unexpectedError(String(describing: error))
        }
        throw RegistryClientErrorCaptureFailure.didNotThrow
    }

    private func makeUnusedAddressReader() -> OpalBase.Network.AddressReader {
        OpalBase.Network.AddressReader(
            fetchBalance: { _, _ in throw RegistryValidatorPlaceholderError.unused },
            fetchUnspentOutputs: { _, _ in throw RegistryValidatorPlaceholderError.unused },
            fetchHistory: { _, _ in throw RegistryValidatorPlaceholderError.unused },
            fetchFirstUse: { _ in throw RegistryValidatorPlaceholderError.unused },
            fetchMempoolTransactions: { _ in throw RegistryValidatorPlaceholderError.unused },
            fetchScriptHash: { _ in throw RegistryValidatorPlaceholderError.unused },
            subscribeToAddress: { _ in throw RegistryValidatorPlaceholderError.unused }
        )
    }

    private func makeChainRegistryTestClient(
        transactionReader: OpalBase.Network.TransactionReader,
        session: URLSession
    ) -> OpalBase.CashTokens.BCMR.Client {
        let scriptHashReader = OpalBase.Network.ScriptHashReader(
            fetchHistory: { _, _ in [] },
            fetchUnspent: { _, _ in [] }
        )
        let authchainResolver = OpalBase.CashTokens.BCMR.Client.AuthchainResolver(
            transactionReader: transactionReader,
            addressReader: makeUnusedAddressReader(),
            scriptHashReader: scriptHashReader,
            maxDepth: 0
        )
        let registryFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )
        return OpalBase.CashTokens.BCMR.Client(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )
    }

    private func makeRegistryTestSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> (URLSession, RegistryRequestRecorder) {
        let recorder = RegistryRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryRedirectURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RegistryRedirectURLProtocol.requestHandler = { request in
            if let url = request.url {
                recorder.append(url)
            }
            return try handler(request)
        }
        return (session, recorder)
    }
}
