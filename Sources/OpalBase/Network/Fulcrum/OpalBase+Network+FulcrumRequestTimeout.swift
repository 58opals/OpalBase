// OpalBase+Network+FulcrumRequestTimeout.swift

import Foundation

extension _OpalBase.Network {
    /// Per-request and subscription-setup RPC timeouts.
    /// These durations do not cap the lifetime of an established socket or subscription stream.
    public struct FulcrumRequestTimeout: Sendable, Equatable {
        public var serverPing: Duration { didSet { serverPing = Self.clampedTimeout(serverPing) } }
        public var serverVersion: Duration { didSet { serverVersion = Self.clampedTimeout(serverVersion) } }
        public var serverFeatures: Duration { didSet { serverFeatures = Self.clampedTimeout(serverFeatures) } }
        public var relayFee: Duration { didSet { relayFee = Self.clampedTimeout(relayFee) } }
        public var feeEstimation: Duration { didSet { feeEstimation = Self.clampedTimeout(feeEstimation) } }
        public var headersTip: Duration { didSet { headersTip = Self.clampedTimeout(headersTip) } }
        public var headersSubscription: Duration { didSet { headersSubscription = Self.clampedTimeout(headersSubscription) } }
        public var addressBalance: Duration { didSet { addressBalance = Self.clampedTimeout(addressBalance) } }
        public var addressUnspent: Duration { didSet { addressUnspent = Self.clampedTimeout(addressUnspent) } }
        public var addressHistory: Duration { didSet { addressHistory = Self.clampedTimeout(addressHistory) } }
        public var addressSubscription: Duration { didSet { addressSubscription = Self.clampedTimeout(addressSubscription) } }
        public var addressFirstUse: Duration { didSet { addressFirstUse = Self.clampedTimeout(addressFirstUse) } }
        public var addressMempool: Duration { didSet { addressMempool = Self.clampedTimeout(addressMempool) } }
        public var addressScriptHash: Duration { didSet { addressScriptHash = Self.clampedTimeout(addressScriptHash) } }
        public var reusablePaymentAddressHistory: Duration { didSet { reusablePaymentAddressHistory = Self.clampedTimeout(reusablePaymentAddressHistory) } }
        public var reusablePaymentAddressMempool: Duration { didSet { reusablePaymentAddressMempool = Self.clampedTimeout(reusablePaymentAddressMempool) } }
        public var scriptHashHistory: Duration { didSet { scriptHashHistory = Self.clampedTimeout(scriptHashHistory) } }
        public var scriptHashUnspent: Duration { didSet { scriptHashUnspent = Self.clampedTimeout(scriptHashUnspent) } }
        public var transactionBroadcast: Duration { didSet { transactionBroadcast = Self.clampedTimeout(transactionBroadcast) } }
        public var transactionConfirmations: Duration { didSet { transactionConfirmations = Self.clampedTimeout(transactionConfirmations) } }
        public var transactionMerkleProof: Duration { didSet { transactionMerkleProof = Self.clampedTimeout(transactionMerkleProof) } }
        public var transactionPositionResolution: Duration { didSet { transactionPositionResolution = Self.clampedTimeout(transactionPositionResolution) } }
        public var mempoolInfo: Duration { didSet { mempoolInfo = Self.clampedTimeout(mempoolInfo) } }
        public var mempoolFeeHistogram: Duration { didSet { mempoolFeeHistogram = Self.clampedTimeout(mempoolFeeHistogram) } }
        
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
            reusablePaymentAddressHistory: Duration = .seconds(15),
            reusablePaymentAddressMempool: Duration = .seconds(8),
            scriptHashHistory: Duration = .seconds(15),
            scriptHashUnspent: Duration = .seconds(10),
            transactionBroadcast: Duration = .seconds(10),
            transactionConfirmations: Duration = .seconds(5),
            transactionMerkleProof: Duration = .seconds(8),
            transactionPositionResolution: Duration = .seconds(8),
            mempoolInfo: Duration = .seconds(5),
            mempoolFeeHistogram: Duration = .seconds(5)
        ) {
            self.serverPing = Self.clampedTimeout(serverPing)
            self.serverVersion = Self.clampedTimeout(serverVersion)
            self.serverFeatures = Self.clampedTimeout(serverFeatures)
            self.relayFee = Self.clampedTimeout(relayFee)
            self.feeEstimation = Self.clampedTimeout(feeEstimation)
            self.headersTip = Self.clampedTimeout(headersTip)
            self.headersSubscription = Self.clampedTimeout(headersSubscription)
            self.addressBalance = Self.clampedTimeout(addressBalance)
            self.addressUnspent = Self.clampedTimeout(addressUnspent)
            self.addressHistory = Self.clampedTimeout(addressHistory)
            self.addressSubscription = Self.clampedTimeout(addressSubscription)
            self.addressFirstUse = Self.clampedTimeout(addressFirstUse)
            self.addressMempool = Self.clampedTimeout(addressMempool)
            self.addressScriptHash = Self.clampedTimeout(addressScriptHash)
            self.reusablePaymentAddressHistory = Self.clampedTimeout(
                reusablePaymentAddressHistory
            )
            self.reusablePaymentAddressMempool = Self.clampedTimeout(
                reusablePaymentAddressMempool
            )
            self.scriptHashHistory = Self.clampedTimeout(scriptHashHistory)
            self.scriptHashUnspent = Self.clampedTimeout(scriptHashUnspent)
            self.transactionBroadcast = Self.clampedTimeout(transactionBroadcast)
            self.transactionConfirmations = Self.clampedTimeout(transactionConfirmations)
            self.transactionMerkleProof = Self.clampedTimeout(transactionMerkleProof)
            self.transactionPositionResolution = Self.clampedTimeout(transactionPositionResolution)
            self.mempoolInfo = Self.clampedTimeout(mempoolInfo)
            self.mempoolFeeHistogram = Self.clampedTimeout(mempoolFeeHistogram)
        }

        private static func clampedTimeout(_ timeout: Duration) -> Duration {
            max(.milliseconds(1), timeout)
        }
    }
}
