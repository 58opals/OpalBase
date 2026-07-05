// OpalBase+ReusablePaymentAddress+Scanner.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct Scanner: Sendable {
        private let performScan: @Sendable (ReceiveCandidate, OpalBase.ReusablePaymentAddress) throws -> ReceiveResult?

        public init(
            scan: @escaping @Sendable (ReceiveCandidate, OpalBase.ReusablePaymentAddress) throws -> ReceiveResult?
        ) {
            self.performScan = scan
        }

        public func scan(
            _ candidate: ReceiveCandidate,
            for reusablePaymentAddress: OpalBase.ReusablePaymentAddress
        ) throws -> ReceiveResult? {
            try performScan(candidate, reusablePaymentAddress)
        }
    }
}
