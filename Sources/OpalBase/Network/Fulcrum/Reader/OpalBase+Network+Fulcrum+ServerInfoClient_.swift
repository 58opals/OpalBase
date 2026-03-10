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
        ) async throws -> SwiftFulcrum.RPC.Response.Result.Server.Version
        func fetchServerFeatures(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.RPC.Response.Result.Server.Features
        func fetchRelayFee(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.RelayFee
        func estimateFee(
            numberOfBlocks: Int,
            options: SwiftFulcrum.Client.Call.Options
        ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.EstimateFee
    }
}

extension _OpalBase.Network.Fulcrum.Client: _OpalBase.Network.Fulcrum.ServerInfoClient {
    func pingServer(options: SwiftFulcrum.Client.Call.Options) async throws {
        _ = try await request(
            method: .server(.ping),
            responseType: SwiftFulcrum.RPC.Response.Result.Server.Ping.self,
            options: options
        )
    }

    func fetchServerVersion(
        clientName: String,
        protocolNegotiation: SwiftFulcrum.Client.Configuration.ProtocolNegotiation.Argument,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Server.Version {
        try await request(
            method: .server(.version(clientName: clientName, protocolNegotiation: protocolNegotiation)),
            responseType: SwiftFulcrum.RPC.Response.Result.Server.Version.self,
            options: options
        )
    }

    func fetchServerFeatures(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.RPC.Response.Result.Server.Features {
        try await request(
            method: .server(.features),
            responseType: SwiftFulcrum.RPC.Response.Result.Server.Features.self,
            options: options
        )
    }

    func fetchRelayFee(options: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.RelayFee {
        try await request(
            method: .blockchain(.relayFee),
            responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.RelayFee.self,
            options: options
        )
    }

    func estimateFee(
        numberOfBlocks: Int,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.RPC.Response.Result.Blockchain.EstimateFee {
        try await request(
            method: .blockchain(.estimateFee(numberOfBlocks: numberOfBlocks)),
            responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.EstimateFee.self,
            options: options
        )
    }
}
