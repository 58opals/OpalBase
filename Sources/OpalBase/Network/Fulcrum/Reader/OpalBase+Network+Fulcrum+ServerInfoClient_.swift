// OpalBase+Network+Fulcrum+ServerInfoClient_.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    protocol ServerInfoClient: Sendable {
        func pingServer(options: SwiftFulcrum.Client.Call.Options) async throws
        func fetchServerVersion(
            clientName: String,
            protocolNegotiation: SwiftFulcrum.Client.Configuration.ProtocolNegotiation.Argument,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Server.Version
        func fetchServerFeatures(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Server.Features
        func fetchRelayFee(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Blockchain.RelayFee
        func estimateFee(
            numberOfBlocks: Int,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.Response.Blockchain.EstimateFee
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.ServerInfoClient {
    func pingServer(options: SwiftFulcrum.Client.Call.Options) async throws {
        _ = try await request(
            .server.ping,
            options: options
        )
    }

    func fetchServerVersion(
        clientName: String,
        protocolNegotiation: SwiftFulcrum.Client.Configuration.ProtocolNegotiation.Argument,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Server.Version {
        try await request(
            .server.version(clientName: clientName, protocolNegotiation: protocolNegotiation),
            options: options
        )
    }

    func fetchServerFeatures(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Server.Features {
        try await request(
            .server.features,
            options: options
        )
    }

    func fetchRelayFee(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Blockchain.RelayFee {
        try await request(
            .blockchain.relayFee,
            options: options
        )
    }

    func estimateFee(
        numberOfBlocks: Int,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.EstimateFee {
        try await request(
            .blockchain.estimateFee(numberOfBlocks: numberOfBlocks),
            options: options
        )
    }
}
