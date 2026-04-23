// OpalBase+Claimable+NetworkStatus.swift

import Foundation

extension _OpalBase.Claimable {
    public struct NetworkStatus {
        public let localStatus: OpalBase.Claimable.LocalStatus
        public let fundingState: OpalBase.Claimable.FundingState
        public let confirmations: UInt?
        public let tipHeight: UInt64?

        public init(
            localStatus: OpalBase.Claimable.LocalStatus,
            fundingState: OpalBase.Claimable.FundingState,
            confirmations: UInt?,
            tipHeight: UInt64?
        ) {
            self.localStatus = localStatus
            self.fundingState = fundingState
            self.confirmations = confirmations
            self.tipHeight = tipHeight
        }
    }
}

extension _OpalBase.Claimable.NetworkStatus: Sendable {}
extension _OpalBase.Claimable.NetworkStatus: Equatable {}
