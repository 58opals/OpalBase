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
        #expect(metadata.source == .embedded)
        
        let expectedDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")
        #expect(metadata.lastUpdated == expectedDate)
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

    @Test("registry fetcher rejects redirects to unsupported schemes")
    func registryFetcherRejectsRedirectsToUnsupportedSchemes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryRedirectURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }

        RegistryRedirectURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw URLError(.badURL) }

            if url.scheme == "https" {
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": "http://registry.example/metadata.json"]
                ))
                return (response, Data())
            }

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data("{}".utf8))
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
