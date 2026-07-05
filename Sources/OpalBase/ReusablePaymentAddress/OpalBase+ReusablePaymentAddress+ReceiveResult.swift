// OpalBase+ReusablePaymentAddress+ReceiveResult.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct ReceiveResult: Sendable, Hashable {
        public let reusablePaymentAddress: OpalBase.ReusablePaymentAddress
        public let candidate: ReceiveCandidate
        public let receivingPublicKey: OpalBase.Key.PublicKey

        public init(
            reusablePaymentAddress: OpalBase.ReusablePaymentAddress,
            candidate: ReceiveCandidate,
            receivingPublicKey: OpalBase.Key.PublicKey
        ) {
            self.reusablePaymentAddress = reusablePaymentAddress
            self.candidate = candidate
            self.receivingPublicKey = receivingPublicKey
        }
    }
}
