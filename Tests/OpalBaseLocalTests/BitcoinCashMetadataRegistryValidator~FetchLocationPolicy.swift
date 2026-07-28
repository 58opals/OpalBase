// BitcoinCashMetadataRegistryValidator~FetchLocationPolicy.swift

import Foundation
import Testing
@testable import OpalBase

extension BitcoinCashMetadataRegistryValidator {
    @Test("registry fetcher rejects local and reserved locations before requesting")
    func rejectDisallowedNetworkLocationsBeforeRequesting() async throws {
        let recorder = RegistryRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryRedirectURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RegistryRedirectURLProtocol.requestHandler = { request in
            if let url = request.url {
                recorder.append(url)
            }
            throw RegistryValidatorPlaceholderError.unused
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            maxBytes: 1_024
        )
        let disallowedResourceIdentifiers = [
            "https://127.0.0.1/metadata.json",
            "https://10.0.0.1/metadata.json",
            "https://169.254.169.254/metadata.json",
            "https://192.0.0.8/metadata.json",
            "https://192.0.2.1/metadata.json",
            "https://[::1]/metadata.json",
            "https://[fc00::1]/metadata.json",
            "https://[2001:db8::1]/metadata.json",
            "https://[3fff::1]/metadata.json",
            "https://[3fff:0fff:ffff::1]/metadata.json",
            "https://localhost/metadata.json",
            "https://registry.local/metadata.json",
            "https://service.home.arpa/metadata.json",
            "https://2130706433/metadata.json",
            "https://127.1/metadata.json"
        ]

        for resourceIdentifier in disallowedResourceIdentifiers {
            await expectDisallowedNetworkLocation {
                _ = try await fetcher.fetchRegistryBytes(from: resourceIdentifier)
            }
        }

        #expect(recorder.values.isEmpty)
    }

    @Test("registry fetcher rejects redirects to private locations before following")
    func rejectPrivateRedirectsBeforeFollowing() async throws {
        let recorder = RegistryRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryRedirectURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RegistryRedirectURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            recorder.append(url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "https://192.168.1.10/metadata.json"]
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

        await expectDisallowedNetworkLocation {
            _ = try await fetcher.fetchRegistryBytes(
                from: "https://registry.example/start"
            )
        }

        #expect(recorder.values.map(\.absoluteString) == [
            "https://registry.example/start"
        ])
    }

    @Test("registry fetcher rejects a private IPFS gateway before requesting")
    func rejectPrivateInterPlanetaryFileSystemGatewayBeforeRequesting() async throws {
        let recorder = RegistryRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryRedirectURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RegistryRedirectURLProtocol.requestHandler = { request in
            if let url = request.url {
                recorder.append(url)
            }
            throw RegistryValidatorPlaceholderError.unused
        }
        defer {
            RegistryRedirectURLProtocol.requestHandler = nil
            session.invalidateAndCancel()
        }
        let gateway = try #require(URL(string: "https://127.0.0.1"))
        let fetcher = OpalBase.CashTokens.BCMR.Client.Fetcher(
            urlSession: session,
            ipfsGateway: gateway,
            maxBytes: 1_024
        )

        await expectDisallowedNetworkLocation {
            _ = try await fetcher.fetchRegistryBytes(
                from: "ipfs://bafybeigdyrzt/registry.json"
            )
        }

        #expect(recorder.values.isEmpty)
    }

    @Test("registry fetcher allows public internet protocol locations")
    func allowPublicInternetProtocolLocations() async throws {
        let recorder = RegistryRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegistryRedirectURLProtocol.self]
        let session = URLSession(configuration: configuration)
        RegistryRedirectURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            recorder.append(url)
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

        _ = try await fetcher.fetchRegistryBytes(
            from: "https://93.184.216.34/metadata.json"
        )
        _ = try await fetcher.fetchRegistryBytes(
            from: "https://192.0.0.9/metadata.json"
        )
        _ = try await fetcher.fetchRegistryBytes(
            from: "https://192.0.1.1/metadata.json"
        )
        _ = try await fetcher.fetchRegistryBytes(
            from: "https://[2606:2800:220:1:248:1893:25c8:1946]/metadata.json"
        )

        #expect(recorder.values.count == 4)
    }

    private func expectDisallowedNetworkLocation(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected the registry fetcher to reject a non-public network location.")
        } catch OpalBase.CashTokens.BCMR.Client.Fetcher.Error.disallowedNetworkLocation(_) {
            return
        } catch {
            Issue.record("Unexpected registry fetch error: \(error)")
        }
    }
}
