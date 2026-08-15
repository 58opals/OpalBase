// OpalBase+Account+MosaicPrivateAlphaRuntime+TerminalDisposition.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Exact package-proven wallet or chain terminal disposition.
    @_spi(MosaicPrivateAlpha)
    public enum TerminalDisposition: Sendable, Equatable {
        case walletReleased
        case chainFinalized(
            transactionHash: Data,
            blockHash: Data,
            confirmations: UInt32
        )

        init(_ disposition: OpalBase.Account.MosaicAttemptTerminalDisposition) {
            switch disposition {
            case .walletReleased:
                self = .walletReleased
            case let .chainFinalized(hash, blockHash, confirmations):
                self = .chainFinalized(
                    transactionHash: hash.naturalOrder,
                    blockHash: blockHash,
                    confirmations: confirmations
                )
            }
        }
    }
}
#endif
