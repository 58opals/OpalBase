// OpalBase+Account+MosaicPrivateAlphaRuntime+ChainState.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Redacted exact-chain recovery state; transaction bytes and wallet references remain private.
    @_spi(MosaicPrivateAlpha)
    public struct ChainState: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let transactionHash: Data
        @_spi(MosaicPrivateAlpha) public let latestPresence: ChainPresence?
        @_spi(MosaicPrivateAlpha) public let holdReason: ChainHoldReason?

        init(_ state: OpalBase.Account.MosaicAttemptChainState) {
            transactionHash = state.transactionHash.naturalOrder
            latestPresence = state.latestObservation.map { observation in
                switch observation.presence {
                case let .present(blockHash, confirmations):
                    return .present(
                        blockHash: blockHash,
                        confirmations: confirmations
                    )
                case .authoritativeAbsence:
                    return .authoritativeAbsence
                }
            }
            holdReason = state.holdReason.map { reason in
                switch reason {
                case .transactionDisappeared:
                    return .transactionDisappeared
                case .blockIdentityChanged:
                    return .blockIdentityChanged
                case .confirmationDepthRetreated:
                    return .confirmationDepthRetreated
                }
            }
        }
    }
}
#endif
