// OpalBase+Account+CashFusionUTXOEligibility.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    public struct CashFusionUTXOEligibility: Sendable, Equatable {
        public enum Status: Sendable, Equatable {
            case eligible
            case blocked(OpalBase.Account.CashFusionBlockedReason)
        }

        public let unspentOutput: OpalBase.Transaction.Output.Unspent
        public let status: Status

        public init(
            unspentOutput: OpalBase.Transaction.Output.Unspent,
            status: Status
        ) {
            self.unspentOutput = unspentOutput
            self.status = status
        }
    }
}
#endif
