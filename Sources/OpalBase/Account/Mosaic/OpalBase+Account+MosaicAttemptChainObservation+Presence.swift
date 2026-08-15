// OpalBase+Account+MosaicAttemptChainObservation+Presence.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.MosaicAttemptChainObservation {
    enum Presence: Sendable, Equatable {
        case present(blockHash: Data?, confirmations: UInt32)
        case authoritativeAbsence
    }
}
#endif
