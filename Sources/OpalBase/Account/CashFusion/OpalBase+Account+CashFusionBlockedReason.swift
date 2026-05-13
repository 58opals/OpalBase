// OpalBase+Account+CashFusionBlockedReason.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    public enum CashFusionBlockedReason: Sendable, Equatable {
        case noEligibleUTXOs
        case tokenUTXO
        case unsupportedLockingScript
    }
}
#endif
