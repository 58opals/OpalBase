// OpalBase+Network+AddressBalance.swift

import Foundation

extension _OpalBase.Network {
    public struct AddressBalance: Sendable, Equatable {
        public let confirmed: UInt64
        public let unconfirmed: Int64
        
        public init(confirmed: UInt64, unconfirmed: Int64) {
            self.confirmed = confirmed
            self.unconfirmed = unconfirmed
        }
    }
}

extension _OpalBase.Network.AddressBalance {
    func confirmedPlusUnconfirmedSatoshi() throws -> OpalBase.Satoshi {
        guard confirmed <= OpalBase.Satoshi.maximumSatoshi else {
            throw OpalBase.Satoshi.Error.exceedsMaximumAmount
        }

        let confirmed = Int64(confirmed)
        let (total, overflow) = confirmed.addingReportingOverflow(unconfirmed)
        guard !overflow else {
            throw OpalBase.Satoshi.Error.exceedsMaximumAmount
        }
        guard total >= 0 else {
            throw OpalBase.Satoshi.Error.negativeResult
        }

        return try OpalBase.Satoshi(UInt64(total))
    }
}
