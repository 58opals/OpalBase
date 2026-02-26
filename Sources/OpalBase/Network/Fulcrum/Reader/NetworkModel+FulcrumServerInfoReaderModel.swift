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
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.ServerModel.PingModel.self,
                    options: .init(timeout: timeouts.serverPing)
                )
            }
        }
        
        public func fetchServerVersion(clientName: String, protocolNegotiation: SwiftFulcrum.FulcrumClient.Configuration.ProtocolNegotiationModel.ArgumentModel) async throws -> FulcrumServerVersionModel {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .server(.version(clientName: clientName, protocolNegotiation: protocolNegotiation)),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.ServerModel.VersionModel.self,
                    options: .init(timeout: timeouts.serverVersion)
                )
                
                return FulcrumServerVersionModel(
                    serverVersion: result.serverVersion,
                    negotiatedProtocolVersion: result.negotiatedProtocolVersion
                )
            }
        }
        
        public func fetchServerFeatures() async throws -> FulcrumServerFeaturesModel {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .server(.features),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.ServerModel.FeaturesModel.self,
                    options: .init(timeout: timeouts.serverFeatures)
                )
                
                return FulcrumServerFeaturesModel(
                    genesisHash: result.genesisHash,
                    hashFunction: result.hashFunction,
                    serverVersion: result.serverVersion,
                    minimumProtocolVersion: result.minimumProtocolVersion,
                    maximumProtocolVersion: result.maximumProtocolVersion,
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
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.RelayFeeModel.self,
                    options: .init(timeout: timeouts.relayFee)
                )
                return result.fee
            }
        }
        
        public func estimateFee(forConfirmationTarget confirmationTarget: Int) async throws -> Double {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.estimateFee(numberOfBlocks: confirmationTarget)),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.EstimateFeeModel.self,
                    options: .init(timeout: timeouts.feeEstimation)
                )
                return result.fee
            }
        }
    }
}
