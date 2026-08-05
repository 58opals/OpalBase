// OpalBase+ReusablePaymentAddress+ReorganizationMetadata.swift

extension _OpalBase.ReusablePaymentAddress {
    /// One trusted chain-reorganization event applied to restoration state.
    public struct ReorganizationMetadata: Codable, Hashable, Sendable {
        public let eventIdentifier: String
        public let firstAffectedHeight: UInt
        public let rollbackHeight: UInt
        public let previousNextUnscannedHeight: UInt

        init(
            eventIdentifier: String,
            firstAffectedHeight: UInt,
            rollbackHeight: UInt,
            previousNextUnscannedHeight: UInt
        ) {
            self.eventIdentifier = eventIdentifier
            self.firstAffectedHeight = firstAffectedHeight
            self.rollbackHeight = rollbackHeight
            self.previousNextUnscannedHeight = previousNextUnscannedHeight
        }
    }
}
