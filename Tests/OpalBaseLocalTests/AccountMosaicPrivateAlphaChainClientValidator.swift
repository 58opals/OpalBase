// AccountMosaicPrivateAlphaChainClientValidator.swift

#if os(macOS)
import Foundation
import SwiftFulcrum
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic private-alpha chain client", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaChainClientValidator {
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime

    @Test("Exact mainnet genesis and reviewed WSS endpoints produce attestation")
    func attestExactMainnetConfiguration() throws {
        let first = try #require(
            URL(string: "wss://fulcrum-a.example:50004")
        )
        let second = try #require(
            URL(string: "wss://fulcrum-b.example:50004")
        )
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [second, first],
            network: .mainnet
        )

        let attestation = try Runtime.validateChainAttestation(
            configuration: configuration,
            features: makeFeatures(genesisHash: Self.mainnetGenesisHash)
        )

        #expect(attestation.network == .mainnet)
        #expect(
            attestation.genesisHash
                == Data(OpalBase.Network.Environment.mainnet.mosaicGenesisHash)
        )
        #expect(attestation.serverURLs == [first, second])
    }

    @Test("Exact endpoint loader ignores every provider fallback")
    func excludeFallbackCatalogs() async throws {
        let reviewed = try #require(
            URL(string: "wss://reviewed.example:50004")
        )
        let fallback = try #require(
            URL(string: "wss://unreviewed.example:50004")
        )
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [reviewed],
            network: .mainnet
        )

        let loaded = try await configuration
            .makeExactFulcrumServerCatalogRepository()
            .loadServers(
                for: SwiftFulcrum.Client.Configuration.Network.mainnet,
                fallback: [fallback]
            )

        #expect(loaded == [reviewed])
    }

    @Test("Only local loopback may use an insecure integration endpoint")
    func permitOnlyInsecureLoopback() throws {
        let loopback = try #require(
            URL(string: "ws://127.0.0.1:62001")
        )
        let accepted = OpalBase.Network.Configuration(
            serverURLs: [loopback],
            network: .mainnet
        )
        #expect(
            try Runtime.validateChainAttestation(
                configuration: accepted,
                features: makeFeatures(
                    genesisHash: Self.mainnetGenesisHash
                )
            ).serverURLs == [loopback]
        )

        let external = OpalBase.Network.Configuration(
            serverURLs: [
                try #require(URL(string: "ws://fulcrum.example:50003"))
            ],
            network: .mainnet
        )
        #expect(throws: Runtime.Failure.invalidNetworkBinding) {
            _ = try Runtime.validateChainAttestation(
                configuration: external,
                features: makeFeatures(
                    genesisHash: Self.mainnetGenesisHash
                )
            )
        }
    }

    @Test("Default catalogs, non-mainnet configuration, and genesis drift fail closed")
    func rejectUnreviewedOrMismatchedNetwork() throws {
        let endpoint = try #require(
            URL(string: "wss://fulcrum.example:50004")
        )
        let features = makeFeatures(genesisHash: Self.mainnetGenesisHash)

        #expect(throws: Runtime.Failure.invalidNetworkBinding) {
            _ = try Runtime.validateChainAttestation(
                configuration: .init(
                    serverURLs: [],
                    network: .mainnet
                ),
                features: features
            )
        }
        #expect(throws: Runtime.Failure.invalidNetworkBinding) {
            _ = try Runtime.validateChainAttestation(
                configuration: .init(
                    serverURLs: [endpoint],
                    network: .chipnet
                ),
                features: features
            )
        }
        #expect(throws: Runtime.Failure.invalidNetworkBinding) {
            _ = try Runtime.validateChainAttestation(
                configuration: .init(
                    serverURLs: [endpoint],
                    network: .mainnet
                ),
                features: makeFeatures(
                    genesisHash: String(repeating: "0", count: 64)
                )
            )
        }
    }

    private static let mainnetGenesisHash =
        "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"

    private func makeFeatures(
        genesisHash: String
    ) -> OpalBase.Network.FulcrumServerFeatures {
        .init(
            genesisHash: genesisHash,
            hashFunction: "sha256",
            serverVersion: "Fulcrum test",
            minimumProtocolVersion: .init(major: 1, minor: 4)!,
            maximumProtocolVersion: .init(major: 1, minor: 5)!,
            pruningLimit: nil,
            hosts: nil,
            hasDoubleSpendProofs: nil,
            hasCashTokens: nil,
            reusablePaymentAddress: nil,
            hasBroadcastPackageSupport: nil
        )
    }
}
#endif
