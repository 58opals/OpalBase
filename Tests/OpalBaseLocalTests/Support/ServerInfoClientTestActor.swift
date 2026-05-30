// ServerInfoClientTestActor.swift

import Foundation
import SwiftFulcrum
@testable import OpalBase

actor ServerInfoClientTestActor: OpalBase.Network.Fulcrum.ServerInfoClient {
    private let pingError: Swift.Error?
    private let featuresError: Swift.Error?
    private let relayFeeError: Swift.Error?
    private let estimatedFeeError: Swift.Error?
    private let versionResponse: SwiftFulcrum.Response.Server.Version
    private let featuresResponse: SwiftFulcrum.Response.Server.Features
    private let relayFeeResponse: SwiftFulcrum.Response.Blockchain.RelayFee
    private let estimatedFeeResponse: SwiftFulcrum.Response.Blockchain.EstimateFee
    private var estimateFeeTargets: [Int] = []

    init(
        pingError: Swift.Error? = nil,
        featuresError: Swift.Error? = nil,
        relayFeeError: Swift.Error? = nil,
        estimatedFeeError: Swift.Error? = nil,
        versionResponse: SwiftFulcrum.Response.Server.Version? = nil,
        featuresResponse: SwiftFulcrum.Response.Server.Features? = nil,
        relayFeeResponse: SwiftFulcrum.Response.Blockchain.RelayFee? = nil,
        estimatedFeeResponse: SwiftFulcrum.Response.Blockchain.EstimateFee? = nil
    ) throws {
        self.pingError = pingError
        self.featuresError = featuresError
        self.relayFeeError = relayFeeError
        self.estimatedFeeError = estimatedFeeError
        self.versionResponse = try versionResponse ?? (
            NetworkFulcrumServerInfoReaderValidator.makeVersionResponse(
                serverVersion: "Fulcrum",
                protocolVersion: "1.4"
            )
        )
        self.featuresResponse = try featuresResponse ?? NetworkFulcrumServerInfoReaderValidator.makeFeaturesResponse()
        self.relayFeeResponse = try relayFeeResponse ?? NetworkFulcrumServerInfoReaderValidator.makeRelayFeeResponse(fee: 0)
        self.estimatedFeeResponse = try estimatedFeeResponse ?? NetworkFulcrumServerInfoReaderValidator.makeEstimateFeeResponse(fee: 0)
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
    ) async throws -> SwiftFulcrum.Response.Server.Version {
        versionResponse
    }

    func fetchServerFeatures(options _: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Server.Features {
        if let featuresError {
            throw featuresError
        }
        return featuresResponse
    }

    func fetchRelayFee(options _: SwiftFulcrum.Client.Call.Options) async throws -> SwiftFulcrum.Response.Blockchain.RelayFee {
        if let relayFeeError {
            throw relayFeeError
        }
        return relayFeeResponse
    }

    func estimateFee(
        numberOfBlocks: Int,
        options _: SwiftFulcrum.Client.Call.Options
    ) async throws -> SwiftFulcrum.Response.Blockchain.EstimateFee {
        estimateFeeTargets.append(numberOfBlocks)
        if let estimatedFeeError {
            throw estimatedFeeError
        }
        return estimatedFeeResponse
    }

    func readEstimateFeeTargets() -> [Int] {
        estimateFeeTargets
    }
}
