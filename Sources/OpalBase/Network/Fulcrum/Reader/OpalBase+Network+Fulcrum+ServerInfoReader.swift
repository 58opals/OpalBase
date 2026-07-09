// OpalBase+Network+Fulcrum+ServerInfoReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public struct ServerInfoReader {
        private let client: any ServerInfoClient
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        
        public init(client: Client, timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()) {
            self.init(client: client as any ServerInfoClient, timeouts: timeouts)
        }

        init(client: any ServerInfoClient, timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func ping() async throws {
            try await OpalBase.Network.performWithFailureTranslation {
                try await client.pingServer(options: .init(timeout: timeouts.serverPing))
            }
        }
        
        public func fetchServerVersion(
            clientName: String,
            minimumProtocolVersion: OpalBase.Network.ProtocolVersion,
            maximumProtocolVersion: OpalBase.Network.ProtocolVersion
        ) async throws -> OpalBase.Network.FulcrumServerVersion {
            try await OpalBase.Network.performWithFailureTranslation {
                guard let minimumVersion = minimumProtocolVersion.swiftFulcrumProtocolVersion,
                      let maximumVersion = maximumProtocolVersion.swiftFulcrumProtocolVersion else {
                    throw OpalBase.Network.Error(
                        reason: .protocolViolation,
                        message: "Invalid protocol version"
                    )
                }

                let protocolNegotiation = try SwiftFulcrum.Client.Configuration.ProtocolNegotiation.Argument(
                    minimumVersion: minimumVersion,
                    maximumVersion: maximumVersion
                )
                
                let result = try await client.fetchServerVersion(
                    clientName: clientName,
                    protocolNegotiation: protocolNegotiation,
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
                let result = try await client.fetchServerFeatures(options: .init(timeout: timeouts.serverFeatures))
                
                return OpalBase.Network.FulcrumServerFeatures(
                    genesisHash: try Self.validateFeatureHash(result.genesisHash, fieldName: "genesis hash"),
                    hashFunction: try Self.validateHashFunction(result.hashFunction),
                    serverVersion: result.serverVersion,
                    minimumProtocolVersion: .init(result.minimumProtocolVersion),
                    maximumProtocolVersion: .init(result.maximumProtocolVersion),
                    pruningLimit: try Self.validateFeatureCount(result.pruningLimit, fieldName: "pruning limit"),
                    hosts: try Self.validateFeatureHosts(result.hosts),
                    hasDoubleSpendProofs: result.hasDoubleSpendProofs,
                    hasCashTokens: result.hasCashTokens,
                    reusablePaymentAddress: try result.reusablePaymentAddress.map { reusable in
                        let historyBlockLimit = try Self.validateFeatureCount(
                            reusable.historyBlockLimit,
                            fieldName: "rpa history block limit"
                        )
                        let maximumHistoryItems = try Self.validateFeatureCount(
                            reusable.maximumHistoryItems,
                            fieldName: "rpa maximum history items"
                        )
                        let indexedPrefixBits = try Self.validateReusablePaymentAddressPrefixBits(
                            reusable.indexedPrefixBits,
                            fieldName: "rpa indexed prefix bits"
                        )
                        let minimumPrefixBits = try Self.validateReusablePaymentAddressPrefixBits(
                            reusable.minimumPrefixBits,
                            fieldName: "rpa minimum prefix bits"
                        )
                        let startingHeight = try Self.validateFeatureCount(
                            reusable.startingHeight,
                            fieldName: "rpa starting height"
                        )
                        try Self.validateReusablePaymentAddressPrefixRange(
                            minimumPrefixBits: minimumPrefixBits,
                            indexedPrefixBits: indexedPrefixBits
                        )
                        
                        return OpalBase.Network.FulcrumServerFeatures.ReusablePaymentAddress(
                            historyBlockLimit: historyBlockLimit,
                            maximumHistoryItems: maximumHistoryItems,
                            indexedPrefixBits: indexedPrefixBits,
                            minimumPrefixBits: minimumPrefixBits,
                            startingHeight: startingHeight
                        )
                    },
                    hasBroadcastPackageSupport: result.hasBroadcastPackageSupport
                )
            }
        }
        
        public func fetchRelayFee() async throws -> Double {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.fetchRelayFee(options: .init(timeout: timeouts.relayFee))
                return try Self.validateFeeRate(result.fee, fieldName: "relay fee")
            }
        }
        
        public func estimateFee(forConfirmationTarget confirmationTarget: Int) async throws -> Double {
            try await OpalBase.Network.performWithFailureTranslation {
                try Self.validateConfirmationTarget(confirmationTarget)
                let result = try await client.estimateFee(
                    numberOfBlocks: confirmationTarget,
                    options: .init(timeout: timeouts.feeEstimation)
                )
                return try Self.validateFeeRate(result.fee, fieldName: "estimated fee")
            }
        }

        private static func validateFeeRate(_ feeRate: Double, fieldName: String) throws -> Double {
            guard feeRate.isFinite, feeRate >= 0 else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid \(fieldName): \(feeRate)"
                )
            }
            return feeRate
        }
        
        private static func validateHashFunction(_ hashFunction: String) throws -> String {
            guard hashFunction == "sha256" else {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Unsupported server feature hash function: \(hashFunction)"
                )
            }
            return hashFunction
        }
        
        private static func validateFeatureCount(_ count: Int?, fieldName: String) throws -> Int? {
            guard let count else { return nil }
            guard count >= 0 else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid server feature \(fieldName): \(count)"
                )
            }
            return count
        }
        
        private static func validateFeaturePort(_ port: Int?, fieldName: String) throws -> Int? {
            guard let port else { return nil }
            guard (1...65_535).contains(port) else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid server feature \(fieldName): \(port)"
                )
            }
            return port
        }

        private static func validateFeatureHosts(
            _ hosts: [String: SwiftFulcrum.Response.Server.Features.Host]?
        ) throws -> [String: OpalBase.Network.FulcrumServerFeatures.Host]? {
            guard let hosts else { return nil }
            var validatedHosts: [String: OpalBase.Network.FulcrumServerFeatures.Host] = .init()
            for (hostName, host) in hosts {
                let validatedHostName = try validateFeatureHostName(hostName)
                let validatedHost = OpalBase.Network.FulcrumServerFeatures.Host(
                    secureSocketsLayerPort: try Self.validateFeaturePort(host.sslPort, fieldName: "ssl port"),
                    transmissionControlProtocolPort: try Self.validateFeaturePort(host.tcpPort, fieldName: "tcp port"),
                    webSocketPort: try Self.validateFeaturePort(host.webSocketPort, fieldName: "websocket port"),
                    secureWebSocketPort: try Self.validateFeaturePort(host.secureWebSocketPort, fieldName: "secure websocket port")
                )
                guard validatedHosts[validatedHostName] == nil else {
                    throw OpalBase.Network.Error(
                        reason: .decoding,
                        message: "Duplicate server feature host: \(validatedHostName)"
                    )
                }
                validatedHosts[validatedHostName] = validatedHost
            }
            return validatedHosts
        }

        private static func validateFeatureHostName(_ hostName: String) throws -> String {
            guard URLHostValidation.isValidUnbracketedHostLiteralOrName(hostName) else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid server feature host: \(hostName)"
                )
            }
            return hostName.lowercased()
        }

        private static func validateReusablePaymentAddressPrefixBits(
            _ count: Int?,
            fieldName: String
        ) throws -> Int? {
            guard let prefixBits = try validateFeatureCount(count, fieldName: fieldName) else { return nil }
            guard prefixBits <= 256 else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid server feature \(fieldName): \(prefixBits)"
                )
            }
            return prefixBits
        }
        
        private static func validateFeatureHash(_ hash: String, fieldName: String) throws -> String {
            _ = try OpalBase.Network.decodeHashData(from: hash, label: "server feature \(fieldName)")
            return hash.lowercased()
        }
        
        private static func validateReusablePaymentAddressPrefixRange(
            minimumPrefixBits: Int?,
            indexedPrefixBits: Int?
        ) throws {
            guard let minimumPrefixBits, let indexedPrefixBits else { return }
            guard minimumPrefixBits <= indexedPrefixBits else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Invalid server feature rpa prefix range: minimum \(minimumPrefixBits) exceeds indexed \(indexedPrefixBits)"
                )
            }
        }
        
        private static func validateConfirmationTarget(_ confirmationTarget: Int) throws {
            guard confirmationTarget > 0 else {
                throw OpalBase.Network.Error(
                    reason: .encoding,
                    message: "Invalid fee confirmation target: \(confirmationTarget)"
                )
            }
        }
    }
}
