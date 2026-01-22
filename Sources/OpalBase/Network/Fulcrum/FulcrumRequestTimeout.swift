// Network+FulcrumRequestTimeout.swift

import Foundation

extension Network {
    public struct FulcrumRequestTimeout: Sendable, Equatable {
        public var serverPing: Duration
        public var serverVersion: Duration
        public var serverFeatures: Duration
        public var relayFee: Duration
        public var feeEstimation: Duration
        public var headersTip: Duration
        public var headersSubscription: Duration
        public var addressBalance: Duration
        public var addressUnspent: Duration
        public var addressHistory: Duration
        public var addressSubscription: Duration
        public var addressFirstUse: Duration
        public var addressMempool: Duration
        public var addressScriptHash: Duration
        public var transactionBroadcast: Duration
        public var transactionConfirmations: Duration
        public var transactionMerkleProof: Duration
        public var transactionPositionResolution: Duration
        public var mempoolInfo: Duration
        public var mempoolFeeHistogram: Duration
        
        public init(
            serverPing: Duration = .seconds(5),
            serverVersion: Duration = .seconds(5),
            serverFeatures: Duration = .seconds(8),
            relayFee: Duration = .seconds(5),
            feeEstimation: Duration = .seconds(8),
            headersTip: Duration = .seconds(5),
            headersSubscription: Duration = .seconds(5),
            addressBalance: Duration = .seconds(5),
            addressUnspent: Duration = .seconds(10),
            addressHistory: Duration = .seconds(15),
            addressSubscription: Duration = .seconds(5),
            addressFirstUse: Duration = .seconds(8),
            addressMempool: Duration = .seconds(8),
            addressScriptHash: Duration = .seconds(5),
            transactionBroadcast: Duration = .seconds(10),
            transactionConfirmations: Duration = .seconds(5),
            transactionMerkleProof: Duration = .seconds(8),
            transactionPositionResolution: Duration = .seconds(8),
            mempoolInfo: Duration = .seconds(5),
            mempoolFeeHistogram: Duration = .seconds(5)
        ) {
            self.serverPing = serverPing
            self.serverVersion = serverVersion
            self.serverFeatures = serverFeatures
            self.relayFee = relayFee
            self.feeEstimation = feeEstimation
            self.headersTip = headersTip
            self.headersSubscription = headersSubscription
            self.addressBalance = addressBalance
            self.addressUnspent = addressUnspent
            self.addressHistory = addressHistory
            self.addressSubscription = addressSubscription
            self.addressFirstUse = addressFirstUse
            self.addressMempool = addressMempool
            self.addressScriptHash = addressScriptHash
            self.transactionBroadcast = transactionBroadcast
            self.transactionConfirmations = transactionConfirmations
            self.transactionMerkleProof = transactionMerkleProof
            self.transactionPositionResolution = transactionPositionResolution
            self.mempoolInfo = mempoolInfo
            self.mempoolFeeHistogram = mempoolFeeHistogram
        }
    }
}
