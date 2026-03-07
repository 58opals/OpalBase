// OpalBase+Network+Fulcrum+ServerInfoReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct ServerInfoReader {
        private let client: Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeoutModel
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeoutModel = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func ping() async throws {
            try await OpalBase.Network.performWithFailureTranslation {
                _ = try await client.request(
                    method: .server(.ping),
                    responseType: SwiftFulcrum.RPC.Response.Result.Server.Ping.self,
                    options: .init(timeout: timeouts.serverPing)
                )
            }
        }
        
        public func fetchServerVersion(
            clientName: String,
            minimumProtocolVersion: OpalBase.Network.ProtocolVersion,
            maximumProtocolVersion: OpalBase.Network.ProtocolVersion
        ) async throws -> OpalBase.Network.FulcrumServerVersion {
            try await OpalBase.Network.performWithFailureTranslation {
                let protocolNegotiation = try SwiftFulcrum.Client.Configuration.ProtocolNegotiation.Argument(
                    minimumVersion: minimumProtocolVersion.swiftFulcrumProtocolVersion,
                    maximumVersion: maximumProtocolVersion.swiftFulcrumProtocolVersion
                )
                
                let result = try await client.request(
                    method: .server(.version(clientName: clientName, protocolNegotiation: protocolNegotiation)),
                    responseType: SwiftFulcrum.RPC.Response.Result.Server.Version.self,
                    options: .init(timeout: timeouts.serverVersion)
                )
                
                return OpalBase.Network.FulcrumServerVersion(
                    serverVersion: result.serverVersion,
                    negotiatedProtocolVersion: .init(result.negotiatedProtocolVersion)
                )
            }
        }
        
        public func fetchServerFeatures() async throws -> OpalBase.Network.FulcrumServerFeatures {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .server(.features),
                    responseType: SwiftFulcrum.RPC.Response.Result.Server.Features.self,
                    options: .init(timeout: timeouts.serverFeatures)
                )
                
                return OpalBase.Network.FulcrumServerFeatures(
                    genesisHash: result.genesisHash,
                    hashFunction: result.hashFunction,
                    serverVersion: result.serverVersion,
                    minimumProtocolVersion: .init(result.minimumProtocolVersion),
                    maximumProtocolVersion: .init(result.maximumProtocolVersion),
                    pruningLimit: result.pruningLimit,
                    hosts: result.hosts?.mapValues { host in
                        OpalBase.Network.FulcrumServerFeatures.Host(
                            secureSocketsLayerPort: host.sslPort,
                            transmissionControlProtocolPort: host.tcpPort,
                            webSocketPort: host.webSocketPort,
                            secureWebSocketPort: host.secureWebSocketPort
                        )
                    },
                    hasDoubleSpendProofs: result.hasDoubleSpendProofs,
                    hasCashTokens: result.hasCashTokens,
                    reusablePaymentAddress: result.reusablePaymentAddress.map { reusable in
                        OpalBase.Network.FulcrumServerFeatures.ReusablePaymentAddress(
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
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.relayFee),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.RelayFee.self,
                    options: .init(timeout: timeouts.relayFee)
                )
                return result.fee
            }
        }
        
        public func estimateFee(forConfirmationTarget confirmationTarget: Int) async throws -> Double {
            try await OpalBase.Network.performWithFailureTranslation {
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
