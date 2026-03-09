// NetworkFulcrumServerInfoReaderValidator.swift

import Foundation
import Testing
import SwiftFulcrum
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.ServerInfoReader", .tags(.unit, .network))
struct NetworkFulcrumServerInfoReaderValidator {
    @Test("maps server info responses into OpalBase types")
    func fetchServerInfoMapsResponses() async throws {
        let expectedMinimumProtocolVersion = try #require(OpalBase.Network.ProtocolVersion(major: 1, minor: 4))
        let expectedMaximumProtocolVersion = try #require(OpalBase.Network.ProtocolVersion(major: 1, minor: 5))
        let client = ServerInfoClientTestActor(
            versionResponse: try Self.makeVersionResponse(serverVersion: "Fulcrum 1.9.0", protocolVersion: "1.5"),
            featuresResponse: try Self.makeFeaturesResponse(),
            relayFeeResponse: .init(fromRPC: 0.00001),
            estimatedFeeResponse: .init(fromRPC: 0.00002)
        )
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(client: client)

        try await reader.ping()
        let version = try await reader.fetchServerVersion(
            clientName: "OpalBase",
            minimumProtocolVersion: expectedMinimumProtocolVersion,
            maximumProtocolVersion: expectedMaximumProtocolVersion
        )
        let features = try await reader.fetchServerFeatures()
        let relayFee = try await reader.fetchRelayFee()
        let estimatedFee = try await reader.estimateFee(forConfirmationTarget: 6)

        #expect(version.serverVersion == "Fulcrum 1.9.0")
        #expect(version.negotiatedProtocolVersion == expectedMaximumProtocolVersion)
        #expect(features.genesisHash == String(repeating: "a", count: 64))
        #expect(features.serverVersion == "Fulcrum 1.9.0")
        #expect(features.minimumProtocolVersion == expectedMinimumProtocolVersion)
        #expect(features.maximumProtocolVersion == expectedMaximumProtocolVersion)
        #expect(features.hosts?["fulcrum.example.com"]?.secureWebSocketPort == 50004)
        #expect(features.hasCashTokens == true)
        #expect(features.reusablePaymentAddress?.startingHeight == 800_000)
        #expect(features.hasBroadcastPackageSupport == true)
        #expect(relayFee == 0.00001)
        #expect(estimatedFee == 0.00002)
    }

    @Test("translates timeout failures for server info requests")
    func pingTranslatesTimeoutFailures() async throws {
        let client = ServerInfoClientTestActor(
            pingError: SwiftFulcrum.Client.Error.client(.timeout(.seconds(3)))
        )
        let reader = OpalBase.Network.Fulcrum.ServerInfoReader(client: client)

        let failure = await Self.captureNetworkError {
            try await reader.ping()
        }

        #expect(failure.reason == .timeout)
        #expect(failure.message == "Operation timed out")
        #expect(failure.metadata["timeoutSeconds"] == "3.0")
    }
}

private actor ServerInfoClientTestActor: OpalBase.Network.Fulcrum.ServerInfoClient {
    private let pingError: Swift.Error?
    private let versionResponse: SwiftFulcrum.RPC.Response.Result.Server.Version
    private let featuresResponse: SwiftFulcrum.RPC.Response.Result.Server.Features
    private let relayFeeResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.RelayFee
    private let estimatedFeeResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.EstimateFee

    init(
        pingError: Swift.Error? = nil,
        versionResponse: SwiftFulcrum.RPC.Response.Result.Server.Version? = nil,
        featuresResponse: SwiftFulcrum.RPC.Response.Result.Server.Features? = nil,
        relayFeeResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.RelayFee = .init(fromRPC: 0),
        estimatedFeeResponse: SwiftFulcrum.RPC.Response.Result.Blockchain.EstimateFee = .init(fromRPC: 0)
    ) {
        self.pingError = pingError
        self.versionResponse = versionResponse ?? (
            try! NetworkFulcrumServerInfoReaderValidator.makeVersionResponse(
                serverVersion: "Fulcrum",
                protocolVersion: "1.4"
            )
        )
        self.featuresResponse = featuresResponse ?? (try! NetworkFulcrumServerInfoReaderValidator.makeFeaturesResponse())
        self.relayFeeResponse = relayFeeResponse
        self.estimatedFeeResponse = estimatedFeeResponse
    }

    func pingServer(options _: SwiftFulcrum.Client.Call.Options) async throws {
        if let pingError {
            throw pingError
        }
    }

    func fetchServerVersion(
        clientName _: String,
        protocolNegotiation _: SwiftFulcrum.Client.Configuration.ProtocolNegotiation.Argument,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Server.Version {
        versionResponse
    }

    func fetchServerFeatures(options _: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.RPC.Response.Result.Server.Features {
        featuresResponse
    }

    func fetchRelayFee(options _: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.RelayFee {
        relayFeeResponse
    }

    func estimateFee(
        numberOfBlocks _: Int,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.EstimateFee {
        estimatedFeeResponse
    }
}

private extension NetworkFulcrumServerInfoReaderValidator {
    static func makeVersionResponse(
        serverVersion: String,
        protocolVersion: String
    ) throws -> SwiftFulcrum.RPC.Response.Result.Server.Version {
        let payload = try JSONSerialization.data(withJSONObject: [serverVersion, protocolVersion])
        let response = try JSONDecoder().decode(SwiftFulcrum.RPC.Response.JSONRPC.Result.Server.Version.self, from: payload)
        return try .init(fromRPC: response)
    }

    static func makeFeaturesResponse() throws -> SwiftFulcrum.RPC.Response.Result.Server.Features {
        let payload = try JSONSerialization.data(withJSONObject: [
            "genesis_hash": String(repeating: "a", count: 64),
            "hash_function": "sha256",
            "server_version": "Fulcrum 1.9.0",
            "protocol_max": "1.5",
            "protocol_min": "1.4",
            "pruning": 100,
            "hosts": ["fulcrum.example.com": ["ssl_port": 50002, "tcp_port": 50001, "ws_port": 50003, "wss_port": 50004]],
            "dsproof": true,
            "cashtokens": true,
            "rpa": ["history_block_limit": 288, "max_history": 100, "prefix_bits": 16, "prefix_bits_min": 8, "starting_height": 800_000],
            "broadcast_package": true
        ])
        let response = try JSONDecoder().decode(SwiftFulcrum.RPC.Response.JSONRPC.Result.Server.Features.self, from: payload)
        return try .init(fromRPC: response)
    }

    static func captureNetworkError(
        _ work: () async throws -> Void
    ) async -> OpalBase.Network.Error {
        do {
            try await work()
            Issue.record("Expected OpalBase.Network.Error")
            return .init(reason: .unknown)
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return .init(reason: .unknown, message: String(describing: error))
        }
    }
}
