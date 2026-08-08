// OpalBase+Account+MosaicTransactionHostActor~Lifecycle.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account.MosaicTransactionHostActor {
    func releaseMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference
    ) async throws {
        try requireMatchingReference(reservationReference)
        if isReleased { return }
        guard !releaseStarted else {
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        }
        guard !commitStarted, committedCompleteTransaction == nil else {
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        }
        guard !finalizationInFlight, !signingStarted, finalizedTransaction == nil else {
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        }

        releaseStarted = true
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
        isReleased = true
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
        if let committedCompleteTransaction {
            guard committedCompleteTransaction == requestedTransaction else {
                throw OpalBase.Account.MosaicHostFailure.conflictingCompleteTransaction
            }
            return
        }
        if let pendingCompleteTransaction {
            guard pendingCompleteTransaction == requestedTransaction else {
                throw OpalBase.Account.MosaicHostFailure.conflictingCompleteTransaction
            }
            guard !commitInFlight else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
        }
        guard !releaseStarted, !isReleased else {
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        }
        guard !finalizationInFlight,
              finalizedRequest != nil,
              finalizedTransaction != nil else {
            throw OpalBase.Account.MosaicHostFailure.finalizationRequired
        }
        guard locallySignedPersisted else {
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        }
        if pendingCompleteTransaction == nil {
            _ = try validateCompleteTransaction(requestedTransaction)
            pendingCompleteTransaction = requestedTransaction
        }

        commitStarted = true
        commitInFlight = true
        defer { commitInFlight = false }
        if !commitIntentPersisted {
            try await persist(
                .commitIntent(
                    reference: reservationReference,
                    transaction: requestedTransaction
                )
            )
            commitIntentPersisted = true
        }
        expirationTask?.cancel()
        for selectedInput in selectedInputs {
            await addressBook.removeUTXO(selectedInput)
        }
        do {
            try await retireReceivingEntries(reservedReceivingEntries)
        } catch {
            throw OpalBase.Account.MosaicHostFailure.reservationCleanupFailed
        }
        try await persist(
            .committed(
                reference: reservationReference,
                transaction: requestedTransaction
            )
        )
        reservedInputs.removeAll()
        committedCompleteTransaction = requestedTransaction
    }

    func expireMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        at date: Date
    ) async throws {
        try requireMatchingReference(reservationReference)
        guard let reservationLease,
              date >= reservationLease.expiresAt,
              !isReleased,
              committedCompleteTransaction == nil else {
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
