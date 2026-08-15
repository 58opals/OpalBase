// OpalBase+Account+MosaicAttemptChainState.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    /// Exact chain-reconciliation state derived from authenticated journal observations.
    struct MosaicAttemptChainState: Sendable, Equatable {
        let reference: OpalFusion.Host.MosaicReservationReference
        let transaction: OpalFusion.Host.MosaicCompleteTransaction
        let transactionHash: OpalBase.Transaction.Hash
        /// The latest exact observation, including authoritative absence.
        let latestObservation: MosaicAttemptChainObservation?
        let holdReason: HoldReason?
    }
}
#endif
