// Network+FulcrumServerInfoReader.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumServerInfoReader {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeout
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func ping() async throws {
            do {
                _ = try await client.request(
                    method: .server(.ping),
                    responseType: Response.Result.Server.Ping.self,
                    options: .init(timeout: timeouts.serverPing)
                )
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func fetchServerVersion(clientName: String, protocolNegotiation: Fulcrum.Configuration.ProtocolNegotiation.Argument) async throws -> FulcrumServerVersion {
            do {
                let result = try await client.request(
                    method: .server(.version(clientName: clientName, protocolNegotiation: protocolNegotiation)),
                    responseType: Response.Result.Server.Version.self,
                    options: .init(timeout: timeouts.serverVersion)
                )
                
                return FulcrumServerVersion(
                    serverVersion: result.serverVersion,
                    negotiatedProtocolVersion: result.negotiatedProtocolVersion
                )
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func fetchServerFeatures() async throws -> FulcrumServerFeatures {
            do {
                let result = try await client.request(
                    method: .server(.features),
                    responseType: Response.Result.Server.Features.self,
                    options: .init(timeout: timeouts.serverFeatures)
                )
                
                return FulcrumServerFeatures(
                    genesisHash: result.genesisHash,
                    hashFunction: result.hashFunction,
                    serverVersion: result.serverVersion,
                    minimumProtocolVersion: result.minimumProtocolVersion,
                    maximumProtocolVersion: result.maximumProtocolVersion,
                    pruningLimit: result.pruningLimit,
                    hosts: result.hosts?.mapValues { host in
                        FulcrumServerFeatures.Host(
                            secureSocketsLayerPort: host.sslPort,
                            transmissionControlProtocolPort: host.tcpPort,
                            webSocketPort: host.webSocketPort,
                            secureWebSocketPort: host.secureWebSocketPort
                        )
                    },
                    hasDoubleSpendProofs: result.hasDoubleSpendProofs,
                    hasCashTokens: result.hasCashTokens,
                    reusablePaymentAddress: result.reusablePaymentAddress.map { reusable in
                        FulcrumServerFeatures.ReusablePaymentAddress(
                            historyBlockLimit: reusable.historyBlockLimit,
                            maximumHistoryItems: reusable.maximumHistoryItems,
                            indexedPrefixBits: reusable.indexedPrefixBits,
                            minimumPrefixBits: reusable.minimumPrefixBits,
                            startingHeight: reusable.startingHeight
                        )
                    },
                    hasBroadcastPackageSupport: result.hasBroadcastPackageSupport
                )
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func fetchRelayFee() async throws -> Double {
            do {
                let result = try await client.request(
                    method: .blockchain(.relayFee),
                    responseType: Response.Result.Blockchain.RelayFee.self,
                    options: .init(timeout: timeouts.relayFee)
                )
                return result.fee
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func estimateFee(forConfirmationTarget confirmationTarget: Int) async throws -> Double {
            do {
                let result = try await client.request(
                    method: .blockchain(.estimateFee(numberOfBlocks: confirmationTarget)),
                    responseType: Response.Result.Blockchain.EstimateFee.self,
                    options: .init(timeout: timeouts.feeEstimation)
                )
                return result.fee
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
    }
}
