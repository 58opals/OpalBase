// Network+AddressBalance.swift

import Foundation

extension Network {
    public struct AddressBalance: Sendable, Equatable {
        public let confirmed: UInt64
        public let unconfirmed: Int64
        
        public init(confirmed: UInt64, unconfirmed: Int64) {
            self.confirmed = confirmed
            self.unconfirmed = unconfirmed
        }
    }
}
