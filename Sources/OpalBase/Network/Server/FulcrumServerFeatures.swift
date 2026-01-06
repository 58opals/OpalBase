// Network+FulcrumServerFeatures.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumServerFeatures: Sendable, Equatable {
        public struct Host: Sendable, Equatable {
            public let secureSocketsLayerPort: Int?
            public let transmissionControlProtocolPort: Int?
            public let webSocketPort: Int?
            public let secureWebSocketPort: Int?
            
            public init(secureSocketsLayerPort: Int?,
                        transmissionControlProtocolPort: Int?,
                        webSocketPort: Int?,
                        secureWebSocketPort: Int?) {
                self.secureSocketsLayerPort = secureSocketsLayerPort
                self.transmissionControlProtocolPort = transmissionControlProtocolPort
                self.webSocketPort = webSocketPort
                self.secureWebSocketPort = secureWebSocketPort
            }
        }
        
        public struct ReusablePaymentAddress: Sendable, Equatable {
            public let historyBlockLimit: Int?
            public let maximumHistoryItems: Int?
            public let indexedPrefixBits: Int?
            public let minimumPrefixBits: Int?
            public let startingHeight: Int?
            
            public init(
                historyBlockLimit: Int?,
                maximumHistoryItems: Int?,
                indexedPrefixBits: Int?,
                minimumPrefixBits: Int?,
                startingHeight: Int?
            ) {
                self.historyBlockLimit = historyBlockLimit
                self.maximumHistoryItems = maximumHistoryItems
                self.indexedPrefixBits = indexedPrefixBits
                self.minimumPrefixBits = minimumPrefixBits
                self.startingHeight = startingHeight
            }
        }
        
        public let genesisHash: String
        public let hashFunction: String
        public let serverVersion: String
        public let minimumProtocolVersion: ProtocolVersion
        public let maximumProtocolVersion: ProtocolVersion
        public let pruningLimit: Int?
        public let hosts: [String: Host]?
        public let hasDoubleSpendProofs: Bool?
        public let hasCashTokens: Bool?
        public let reusablePaymentAddress: ReusablePaymentAddress?
        public let hasBroadcastPackageSupport: Bool?
        
        public init(
            genesisHash: String,
            hashFunction: String,
            serverVersion: String,
            minimumProtocolVersion: ProtocolVersion,
            maximumProtocolVersion: ProtocolVersion,
            pruningLimit: Int?,
            hosts: [String: Host]?,
            hasDoubleSpendProofs: Bool?,
            hasCashTokens: Bool?,
            reusablePaymentAddress: ReusablePaymentAddress?,
            hasBroadcastPackageSupport: Bool?
        ) {
            self.genesisHash = genesisHash
            self.hashFunction = hashFunction
            self.serverVersion = serverVersion
            self.minimumProtocolVersion = minimumProtocolVersion
            self.maximumProtocolVersion = maximumProtocolVersion
            self.pruningLimit = pruningLimit
            self.hosts = hosts
            self.hasDoubleSpendProofs = hasDoubleSpendProofs
            self.hasCashTokens = hasCashTokens
            self.reusablePaymentAddress = reusablePaymentAddress
            self.hasBroadcastPackageSupport = hasBroadcastPackageSupport
        }
    }
}
