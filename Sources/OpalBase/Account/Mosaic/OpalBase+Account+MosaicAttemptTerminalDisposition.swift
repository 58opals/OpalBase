// OpalBase+Account+MosaicAttemptTerminalDisposition.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    /// Package-proven terminal wallet or chain disposition for one exact attempt.
    enum MosaicAttemptTerminalDisposition: Sendable, Equatable {
        case walletReleased
        case chainFinalized(
            transactionHash: OpalBase.Transaction.Hash,
            blockHash: Data,
            confirmations: UInt32
        )
    }
}
#endif
