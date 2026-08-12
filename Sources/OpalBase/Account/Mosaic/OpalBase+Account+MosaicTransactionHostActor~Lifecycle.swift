// OpalBase+Account+MosaicTransactionHostActor~Lifecycle.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account.MosaicTransactionHostActor {
    func releaseMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference
    ) async throws {
        try requireMatchingReference(reservationReference)
        switch lifecycle {
        case .released:
            return
        case .releaseIntent, .validating, .signingIntent,
             .localSignaturePending, .localSignaturePersisting, .locallySigned:
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        case .commitPending, .commitIntentPersisting, .commitRecovery,
             .committing, .committed:
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        case .idle, .reservationIntent:
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        case .reserved, .finalizationPending:
            break
        }

        lifecycle = .releaseIntent
        try await persist(.releaseIntent(reservationReference))
        expirationTask?.cancel()
        await addressBook.releaseUTXOs(Set(selectedInputs))
        do {
            try await retireReceivingEntries(reservedReceivingEntries)
        } catch {
            throw OpalBase.Account.MosaicHostFailure.reservationCleanupFailed
        }
        reservedInputs.removeAll()
        pendingFinalizationRequest = nil
        finalizedRequest = nil
        finalizedTransaction = nil
        try await persist(.released(reservationReference))
        lifecycle = .released
    }

    func commitMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        finalizedTransaction _: OpalFusion.Host.FinalizedTransaction
    ) async throws {
        try requireMatchingReference(reservationReference)
        throw OpalBase.Account.MosaicHostFailure.completeTransactionRequired
    }

    func commitMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        completeTransaction requestedTransaction: OpalFusion.Host.MosaicCompleteTransaction
    ) async throws {
        try requireMatchingReference(reservationReference)
        switch lifecycle {
        case .committed:
            guard let committedCompleteTransaction else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard committedCompleteTransaction == requestedTransaction else {
                throw OpalBase.Account.MosaicHostFailure.conflictingCompleteTransaction
            }
            return
        case .commitIntentPersisting, .committing:
            guard let pendingCompleteTransaction else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard pendingCompleteTransaction == requestedTransaction else {
                throw OpalBase.Account.MosaicHostFailure.conflictingCompleteTransaction
            }
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        case .commitPending, .commitRecovery:
            guard let pendingCompleteTransaction else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard pendingCompleteTransaction == requestedTransaction else {
                throw OpalBase.Account.MosaicHostFailure.conflictingCompleteTransaction
            }
        case .releaseIntent, .released:
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        case .validating, .localSignaturePersisting, .reserved,
             .finalizationPending, .signingIntent:
            throw OpalBase.Account.MosaicHostFailure.finalizationRequired
        case .localSignaturePending:
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        case .locallySigned:
            guard finalizedRequest != nil,
                  finalizedTransaction != nil,
                  pendingCompleteTransaction == nil else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            _ = try validateCompleteTransaction(requestedTransaction)
            pendingCompleteTransaction = requestedTransaction
            lifecycle = .commitPending
        case .idle, .reservationIntent:
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        }

        switch lifecycle {
        case .commitPending:
            lifecycle = .commitIntentPersisting
            do {
                try await persist(
                    .commitIntent(
                        reference: reservationReference,
                        transaction: requestedTransaction
                    )
                )
            } catch {
                lifecycle = .commitPending
                throw error
            }
            lifecycle = .committing
        case .commitRecovery:
            lifecycle = .committing
        default:
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        }

        do {
            expirationTask?.cancel()
            for selectedInput in selectedInputs {
                await addressBook.removeUTXO(selectedInput)
            }
            try await retireReceivingEntries(reservedReceivingEntries)
            try await persist(
                .committed(
                    reference: reservationReference,
                    transaction: requestedTransaction
                )
            )
        } catch {
            lifecycle = .commitRecovery
            throw error
        }
        reservedInputs.removeAll()
        committedCompleteTransaction = requestedTransaction
        lifecycle = .committed
    }

    func expireMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        at date: Date
    ) async throws {
        try requireMatchingReference(reservationReference)
        guard let reservationLease,
              date >= reservationLease.expiresAt,
              lifecycle != .released,
              lifecycle != .committed else {
            return
        }
        try await releaseMosaicReservation(reservationReference)
    }

    func requireMatchingReference(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference
    ) throws {
        guard let reservationLease else {
            throw OpalBase.Account.MosaicHostFailure.reservationUnavailable
        }
        guard reservationLease.reference == reservationReference else {
            throw OpalBase.Account.MosaicHostFailure.staleReservationReference
        }
    }

    func retireReceivingEntries(
        _ entries: [OpalBase.Address.Book.Entry]
    ) async throws {
        var didFail = false
        for entry in entries {
            do {
                _ = try await addressBook.releaseReservation(
                    address: entry.address,
                    shouldKeepUsed: true
                )
            } catch {
                didFail = true
            }
        }
        guard !didFail else {
            throw OpalBase.Account.MosaicHostFailure.reservationCleanupFailed
        }
    }
}
#endif
