// NetworkModel+AddressBalanceModel.swift

import Foundation

extension NetworkModel {
    public struct AddressBalanceModel: Sendable, Equatable {
        public let confirmed: UInt64
        public let unconfirmed: Int64
        
        public init(confirmed: UInt64, unconfirmed: Int64) {
            self.confirmed = confirmed
            self.unconfirmed = unconfirmed
        }
    }
}
