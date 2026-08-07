// OpalBase+Account+MosaicHostFailure.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    enum MosaicHostFailure: Swift.Error, Sendable, Equatable {
        case mainnetUnavailable
        case invalidNetworkBinding
        case invalidContributionPolicy
        case reservationUnavailable
        case reservationExpired
        case inPlaceRetryNotPermitted
        case staleReservationReference
        case terminalReservation
        case reservationCleanupFailed
        case invalidTransactionProposal
        case transactionPolicyRejected
        case conflictingFinalization
        case conflictingCompleteTransaction
        case finalizationRequired
        case completeTransactionRequired
        case invalidCompleteTransaction
        case reconciliationRequired
        case journalPersistenceFailed
        case conflictingBroadcast
    }
}
#endif
