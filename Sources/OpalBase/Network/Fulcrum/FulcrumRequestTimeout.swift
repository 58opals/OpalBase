// Network+FulcrumRequestTimeout.swift

import Foundation

extension Network {
    public struct FulcrumRequestTimeout: Sendable, Equatable {
        public var headersTip: Duration
        public var headersSubscription: Duration
        public var addressBalance: Duration
        public var addressUnspent: Duration
        public var addressHistory: Duration
        public var addressSubscription: Duration
        public var transactionBroadcast: Duration
        public var transactionConfirmations: Duration
        
        public init(
            headersTip: Duration = .seconds(5),
            headersSubscription: Duration = .seconds(5),
            addressBalance: Duration = .seconds(5),
            addressUnspent: Duration = .seconds(10),
            addressHistory: Duration = .seconds(15),
            addressSubscription: Duration = .seconds(5),
            transactionBroadcast: Duration = .seconds(10),
            transactionConfirmations: Duration = .seconds(5)
        ) {
            self.headersTip = headersTip
            self.headersSubscription = headersSubscription
            self.addressBalance = addressBalance
            self.addressUnspent = addressUnspent
            self.addressHistory = addressHistory
            self.addressSubscription = addressSubscription
            self.transactionBroadcast = transactionBroadcast
            self.transactionConfirmations = transactionConfirmations
        }
    }
}
