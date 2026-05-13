// OpalBase+Account+CashFusionAccountStatus.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    public enum CashFusionAccountStatus: Sendable, Equatable {
        case ready
        case blocked(OpalBase.Account.CashFusionBlockedReason)
    }
}
#endif
