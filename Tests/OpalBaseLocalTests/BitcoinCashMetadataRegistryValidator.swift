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

    @Test("parses sliced publication output script")
    func parseSlicedPublicationOutputScript() throws {
        let script = BitcoinCashMetadataRegistryTestData.publicationScript
        let paddedScript = Data([0x00]) + script
        let slicedScript = paddedScript[paddedScript.index(after: paddedScript.startIndex)...]

        let publication = try #require(
            OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(lockingScript: slicedScript)
        )

        #expect(slicedScript.startIndex != 0)
        #expect(publication.sha256 == BitcoinCashMetadataRegistryTestData.publicationHash)
        #expect(
            publication.uris == [
                BitcoinCashMetadataRegistryTestData.publicationUniformResourceIdentifier
            ]
        )
    }

    @Test("rejects publication marker after leading script bytes")
    func rejectsPublicationMarkerAfterLeadingScriptBytes() {
        var script = Data([ScriptOperationCode._1.rawValue])
        script.append(BitcoinCashMetadataRegistryTestData.publicationScript)

        let publication = OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(
            lockingScript: script
        )

        #expect(publication == nil)
    }
    
    @Test("rejects publication outputs without registry locations")
    func rejectsPublicationOutputsWithoutRegistryLocations() {
        let prefix = Data([0x42, 0x43, 0x4d, 0x52])
        var script = Data([0x6a])
        script.append(Data.push(prefix))
        script.append(Data.push(BitcoinCashMetadataRegistryTestData.publicationHash))
        
        let publication = OpalBase.CashTokens.BCMR.Client.parsePublicationOutput(
            lockingScript: script
        )
        
        #expect(publication == nil)
    }
    
    @Test("verifies registry hash")
    func verifyRegistryHash() {
        let registryHash = OpalCrypto.Hashing.sha256(BitcoinCashMetadataRegistryTestData.registryData)
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
        #expect(metadata.description == "Example token description")
        #expect(metadata.webURL == nil)
        #expect(metadata.identity == "example.identity")
        #expect(metadata.authbase == nil)
        #expect(metadata.registryURL == nil)
        #expect(metadata.source == .embedded)
        
        let expectedDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")
        #expect(metadata.lastUpdated == expectedDate)
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
                            "icon": BitcoinCashMetadataRegistryTestData.registryIconLocation.absoluteString,
                            "web": webURL.absoluteString,
                            "registry": registryURL.absoluteString
                        ]
                    )
                ]
            ]
        )

        let metadata = try #require(
            registries.extractTokenMetadata(from: registry)[BitcoinCashMetadataRegistryTestData.categoryIdentifier]
        )

        #expect(metadata.name == "Rich Token")
        #expect(metadata.symbol == "RICH")
        #expect(metadata.decimals == 8)
        #expect(metadata.description == "Rich token description")
        #expect(metadata.iconURL == BitcoinCashMetadataRegistryTestData.registryIconLocation)
        #expect(metadata.webURL == webURL)
        #expect(metadata.identity == identityHexadecimal)
        #expect(metadata.authbase == identityAuthbase)
        #expect(metadata.registryURL == registryURL)
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

        do {
            _ = try await client.importRegistry(from: "https://registry.example/registry.json")
            Issue.record("Expected prefixed registry identity to be rejected")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Error {
            guard case .invalidRegistryIdentity(let failedIdentity, _) = error else {
                Issue.record("Expected invalidRegistryIdentity, got \(error)")
                return
            }
            #expect(failedIdentity == registryIdentity)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
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
            registries.extractTokenMetadata(from: registry)[BitcoinCashMetadataRegistryTestData.categoryIdentifier]
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
            registries.extractTokenMetadata(from: registry)[BitcoinCashMetadataRegistryTestData.categoryIdentifier]
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
            registries.extractTokenMetadata(from: registry)[BitcoinCashMetadataRegistryTestData.categoryIdentifier]
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
    
    @Test("authchain transaction decode rejects trailing payload bytes")
    func authchainTransactionDecodeRejectsTrailingPayloadBytes() throws {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x44, count: 32))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(value: 0, lockingScript: Data([ScriptOperationCode._1.rawValue]))
        let transaction = OpalBase.Transaction(
            version: 1,
            inputs: [input],
            outputs: [output],
            lockTime: 0
        )
        let rawTransactionData = try transaction.encode() + Data([0x00])
        
        do {
            _ = try OpalBase.CashTokens.BCMR.Client.AuthchainResolver.decodeTransaction(
                rawTransactionData,
                transactionHash: transactionHash
            )
            Issue.record("Expected authchain decode to reject trailing bytes")
        } catch let error as OpalBase.CashTokens.BCMR.Client.AuthchainResolver.Error {
            guard case .transactionDecodingFailed(let failedHash, let underlying) = error else {
                Issue.record("Expected transactionDecodingFailed, got \(error)")
                return
            }
            #expect(failedHash == transactionHash)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .decoding)
            #expect(networkError.message == "Transaction payload has trailing bytes")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("chain registry resolution rejects trailing authhead payload bytes")
    func chainRegistryResolutionRejectsTrailingAuthheadPayloadBytes() async throws {
        let registryURI = "https://registry.example/registry.json"
        let publicationScript = makePublicationScript(
            sha256: BitcoinCashMetadataRegistryTestData.registryHash,
            uris: [registryURI]
        )
        let authbase = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x63, count: 32))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x62, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(value: 0, lockingScript: publicationScript)
        let transaction = OpalBase.Transaction(
            version: 1,
            inputs: [input],
            outputs: [output],
            lockTime: 0
        )
        let rawTransactionData = try transaction.encode()
        let rawTransactions = RawTransactionSequence([
            rawTransactionData,
            rawTransactionData + Data([0x00])
        ])
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            try rawTransactions.next()
        }
        let addressReader = makeUnusedAddressReader()
        let scriptHashReader = OpalBase.Network.ScriptHashReader(
            fetchHistory: { _, _ in [] },
            fetchUnspent: { _, _ in [] }
        )
        let authchainResolver = OpalBase.CashTokens.BCMR.Client.AuthchainResolver(
            transactionReader: transactionReader,
            addressReader: addressReader,
            scriptHashReader: scriptHashReader,
            maxDepth: 0
        )
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
        let registryFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )
        let client = OpalBase.CashTokens.BCMR.Client(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )

        do {
            _ = try await client.resolveChainRegistry(authbase: authbase)
            Issue.record("Expected chain registry resolution to reject trailing transaction bytes")
        } catch let error as OpalBase.CashTokens.BCMR.Client.AuthchainResolver.Error {
            guard case .transactionDecodingFailed(let failedHash, let underlying) = error else {
                Issue.record("Expected transactionDecodingFailed, got \(error)")
                return
            }
            #expect(failedHash == authbase)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .decoding)
            #expect(networkError.message == "Transaction payload has trailing bytes")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("chain registry resolution falls back across publication URIs")
    func chainRegistryResolutionFallsBackAcrossPublicationURIs() async throws {
        let primaryURI = "https://registry.example/missing.json"
        let fallbackURI = "https://registry.example/registry.json"
        let publicationScript = makePublicationScript(
            sha256: BitcoinCashMetadataRegistryTestData.registryHash,
            uris: [primaryURI, fallbackURI]
        )
        let authbase = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x64, count: 32))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x65, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(value: 0, lockingScript: publicationScript)
        let transaction = OpalBase.Transaction(
            version: 1,
            inputs: [input],
            outputs: [output],
            lockTime: 0
        )
        let rawTransactionData = try transaction.encode()
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            rawTransactionData
        }
        let addressReader = makeUnusedAddressReader()
        let scriptHashReader = OpalBase.Network.ScriptHashReader(
            fetchHistory: { _, _ in [] },
            fetchUnspent: { _, _ in [] }
        )
        let authchainResolver = OpalBase.CashTokens.BCMR.Client.AuthchainResolver(
            transactionReader: transactionReader,
            addressReader: addressReader,
            scriptHashReader: scriptHashReader,
            maxDepth: 0
        )
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
        let registryFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )
        let client = OpalBase.CashTokens.BCMR.Client(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
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
            sha256: BitcoinCashMetadataRegistryTestData.registryHash,
            uris: [primaryURI, fallbackURI]
        )
        let authbase = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x66, count: 32))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x67, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(value: 0, lockingScript: publicationScript)
        let transaction = OpalBase.Transaction(
            version: 1,
            inputs: [input],
            outputs: [output],
            lockTime: 0
        )
        let rawTransactionData = try transaction.encode()
        let transactionReader = OpalBase.Network.TransactionReader { _ in
            rawTransactionData
        }
        let addressReader = makeUnusedAddressReader()
        let scriptHashReader = OpalBase.Network.ScriptHashReader(
            fetchHistory: { _, _ in [] },
            fetchUnspent: { _, _ in [] }
        )
        let authchainResolver = OpalBase.CashTokens.BCMR.Client.AuthchainResolver(
            transactionReader: transactionReader,
            addressReader: addressReader,
            scriptHashReader: scriptHashReader,
            maxDepth: 0
        )
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
        let registryFetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )
        let client = OpalBase.CashTokens.BCMR.Client(
            authchainResolver: authchainResolver,
            registryFetcher: registryFetcher
        )

        let resolved = try await client.resolveChainRegistry(authbase: authbase)

        #expect(resolved.registry.version == "1")
        #expect(requestedURLs.values.map(\.absoluteString) == [primaryURI, fallbackURI])
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
        _ = try await fetcher.fetchRegistry(from: "https://example.com")
        _ = try await fetcher.fetchRegistry(from: "https://example.com/")
        _ = try await fetcher.fetchRegistry(from: "https://example.com/registry.json")

        #expect(requestedURLs.values.map(\.absoluteString) == [
            "https://otr.cash/.well-known/bitcoin-cash-metadata-registry.json",
            "https://example.com/.well-known/bitcoin-cash-metadata-registry.json",
            "https://example.com/.well-known/bitcoin-cash-metadata-registry.json",
            "https://example.com/.well-known/bitcoin-cash-metadata-registry.json",
            "https://example.com/registry.json"
        ])
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

        do {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt")
            Issue.record("Expected missingInterPlanetaryFileSystemGateway.")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            switch error {
            case .missingInterPlanetaryFileSystemGateway:
                break
            default:
                Issue.record("Expected missingInterPlanetaryFileSystemGateway, got \(error).")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    @Test("registry fetcher rejects insecure IPFS gateways before fetching")
    func registryFetcherRejectsInsecureInterPlanetaryFileSystemGateways() async throws {
        let gateway = try #require(URL(string: "http://gateway.example"))
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            ipfsGateway: gateway,
            maxBytes: 1_024
        )
        
        do {
            _ = try await fetcher.fetchRegistryBytes(from: "ipfs://bafybeigdyrzt")
            Issue.record("Expected insecure IPFS gateway to be rejected before fetching")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            switch error {
            case .invalidInterPlanetaryFileSystemGateway(gateway):
                break
            default:
                Issue.record("Expected invalidInterPlanetaryFileSystemGateway, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
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

        do {
            _ = try await fetcher.fetchRegistryBytes(from: "https://registry.example/metadata.json")
            Issue.record("Expected responseTooLarge.")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            switch error {
            case .responseTooLarge(limit: 4, actual: 5):
                break
            default:
                Issue.record("Expected responseTooLarge(limit: 4, actual: 5), got \(error).")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
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

    @Test("registry fetcher does not return cache expiry for no-store responses")
    func registryFetcherDoesNotReturnCacheExpiryForNoStoreResponses() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Cache-Control": "no-store, max-age=60"]
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

    @Test("registry fetcher does not return cache expiry for no-cache responses")
    func registryFetcherDoesNotReturnCacheExpiryForNoCacheResponses() async throws {
        let (session, _) = makeRegistryTestSession { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Cache-Control": "no-cache, max-age=60"]
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

        do {
            _ = try await fetcher.fetchRegistryBytes(
                from: "https://registry.example/metadata.json"
            )
            Issue.record("Expected unsupportedScheme for HTTP redirect.")
        } catch let error as OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            switch error {
            case .unsupportedScheme("http"):
                break
            default:
                Issue.record("Expected unsupportedScheme(\"http\"), got \(error).")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
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

private enum RegistryValidatorPlaceholderError: Swift.Error {
    case unused
}

private final class RawTransactionSequence: @unchecked Sendable {
    enum Error: Swift.Error {
        case exhausted
    }

    private let lock = NSLock()
    private var values: [Data]

    init(_ values: [Data]) {
        self.values = values
    }

    func next() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { throw Error.exhausted }
        return values.removeFirst()
    }
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

private final class RegistryRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requestedURLs: [URL] = .init()

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return requestedURLs
    }

    func append(_ url: URL) {
        lock.lock()
        requestedURLs.append(url)
        lock.unlock()
    }
}

private final class RegistryRedirectURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
