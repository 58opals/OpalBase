// OpalBase+ReusablePaymentAddress+TransactionInputMetadata.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct TransactionInputMetadata: Sendable, Hashable {
        public let outpoint: OpalBase.Transaction.Outpoint
        public let inputPublicKey: OpalBase.Key.PublicKey
        public let inputHashPrefix: InputHashPrefix

        public init(
            outpoint: OpalBase.Transaction.Outpoint,
            inputPublicKey: OpalBase.Key.PublicKey,
            inputHashPrefix: InputHashPrefix
        ) {
            self.outpoint = outpoint
            self.inputPublicKey = inputPublicKey
            self.inputHashPrefix = inputHashPrefix
        }
    }
}
