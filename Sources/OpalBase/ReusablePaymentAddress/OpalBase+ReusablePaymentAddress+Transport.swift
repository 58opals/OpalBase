// OpalBase+ReusablePaymentAddress+Transport.swift

extension _OpalBase.ReusablePaymentAddress {
    /// Explicit candidate and raw-transaction dependencies for restoration.
    public struct Transport: Sendable {
        public let candidates: OpalBase.Network.ReusablePaymentAddressReader
        public let transactions: OpalBase.Network.TransactionReader

        public init(
            candidates: OpalBase.Network.ReusablePaymentAddressReader,
            transactions: OpalBase.Network.TransactionReader
        ) {
            self.candidates = candidates
            self.transactions = transactions
        }
    }
}
