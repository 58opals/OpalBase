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

    @Test("rejects publication marker after leading script bytes")
    func rejectsPublicationMarkerAfterLeadingScriptBytes() {
        var script = Data([ScriptOperationCode._1.rawValue])
        script.append(BitcoinCashMetadataRegistryTestData.publicationScript)

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
