// OpalBase+Account+MosaicPrivateAlphaRuntime+ChainPresence.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Latest exact chain presence retained by authenticated recovery state.
    @_spi(MosaicPrivateAlpha)
    public enum ChainPresence: Sendable, Equatable {
        case present(blockHash: Data?, confirmations: UInt32)
        case authoritativeAbsence
    }
}
#endif
