// NetworkModel+FulcrumServerInfoReaderModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct FulcrumServerInfoReaderModel {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeoutModel
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeoutModel = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func ping() async throws {
            try await NetworkModel.performWithFailureTranslation {
                _ = try await client.request(
                    method: .server(.ping),
                    responseType: SwiftFulcrum.RPC.Response.Result.Server.Ping.self,
                    options: .init(timeout: timeouts.serverPing)
                )
            }
        }
        
        public func fetchServerVersion(
            clientName: String,
            minimumProtocolVersion: NetworkModel.ProtocolVersion,
            maximumProtocolVersion: NetworkModel.ProtocolVersion
        ) async throws -> FulcrumServerVersionModel {
            try await NetworkModel.performWithFailureTranslation {
                let protocolNegotiation = try SwiftFulcrum.Client.Configuration.ProtocolNegotiation.Argument(
                    minimumVersion: minimumProtocolVersion.swiftFulcrumProtocolVersion,
                    maximumVersion: maximumProtocolVersion.swiftFulcrumProtocolVersion
                )
                
                let result = try await client.request(
                    method: .server(.version(clientName: clientName, protocolNegotiation: protocolNegotiation)),
                    responseType: SwiftFulcrum.RPC.Response.Result.Server.Version.self,
                    options: .init(timeout: timeouts.serverVersion)
                )
                
                return FulcrumServerVersionModel(
                    serverVersion: result.serverVersion,
                    negotiatedProtocolVersion: .init(result.negotiatedProtocolVersion)
                )
            }
        }
        
        public func fetchServerFeatures() async throws -> FulcrumServerFeaturesModel {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .server(.features),
                    responseType: SwiftFulcrum.RPC.Response.Result.Server.Features.self,
                    options: .init(timeout: timeouts.serverFeatures)
                )
                
                return FulcrumServerFeaturesModel(
                    genesisHash: result.genesisHash,
                    hashFunction: result.hashFunction,
                    serverVersion: result.serverVersion,
                    minimumProtocolVersion: .init(result.minimumProtocolVersion),
                    maximumProtocolVersion: .init(result.maximumProtocolVersion),
                    pruningLimit: result.pruningLimit,
                    hosts: result.hosts?.mapValues { host in
                        FulcrumServerFeaturesModel.Host(
                            secureSocketsLayerPort: host.sslPort,
                            transmissionControlProtocolPort: host.tcpPort,
                            webSocketPort: host.webSocketPort,
                            secureWebSocketPort: host.secureWebSocketPort
                        )
                    },
                    hasDoubleSpendProofs: result.hasDoubleSpendProofs,
                    hasCashTokens: result.hasCashTokens,
                    reusablePaymentAddress: result.reusablePaymentAddress.map { reusable in
                        FulcrumServerFeaturesModel.ReusablePaymentAddress(
                            historyBlockLimit: reusable.historyBlockLimit,
                            maximumHistoryItems: reusable.maximumHistoryItems,
                            indexedPrefixBits: reusable.indexedPrefixBits,
                            minimumPrefixBits: reusable.minimumPrefixBits,
                            startingHeight: reusable.startingHeight
                        )
                    },
                    hasBroadcastPackageSupport: result.hasBroadcastPackageSupport
                )
            }
        }
        
        public func fetchRelayFee() async throws -> Double {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.relayFee),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.RelayFee.self,
                    options: .init(timeout: timeouts.relayFee)
                )
                return result.fee
            }
        }
        
        public func estimateFee(forConfirmationTarget confirmationTarget: Int) async throws -> Double {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.estimateFee(numberOfBlocks: confirmationTarget)),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.EstimateFee.self,
                    options: .init(timeout: timeouts.feeEstimation)
                )
                return result.fee
            }
        }
    }
}
