#if os(macOS)
// OpalBase+Account+CashFusionBlockedReason.swift

import Foundation

extension _OpalBase.Account {
    public enum CashFusionBlockedReason: Sendable, Equatable {
        case noEligibleUTXOs
        case tokenUTXO
        case unsupportedLockingScript
    }
}
#endif
