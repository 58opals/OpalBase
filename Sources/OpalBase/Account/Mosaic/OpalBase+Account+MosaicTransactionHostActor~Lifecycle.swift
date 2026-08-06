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
        guard !commitStarted, committedTransaction == nil else {
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        }

        releaseStarted = true
        expirationTask?.cancel()
        await addressBook.releaseUTXOs(Set(selectedInputs))
        do {
            try await retireReceivingEntries(reservedReceivingEntries)
        } catch {
            throw OpalBase.Account.MosaicHostFailure.reservationCleanupFailed
        }
        reservedInputs.removeAll()
        finalizedRequest = nil
        finalizedTransaction = nil
        isReleased = true
    }

    func commitMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        finalizedTransaction requestedTransaction: OpalFusion.Host.FinalizedTransaction
    ) async throws {
        try requireMatchingReference(reservationReference)
        if let committedTransaction {
            guard committedTransaction == requestedTransaction else {
                throw OpalBase.Account.MosaicHostFailure.conflictingFinalization
            }
            return
        }
        guard !releaseStarted, !isReleased else {
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        }
        guard finalizedTransaction == requestedTransaction else {
            throw OpalBase.Account.MosaicHostFailure.finalizationRequired
        }

        commitStarted = true
        expirationTask?.cancel()
        for selectedInput in selectedInputs {
            await addressBook.removeUTXO(selectedInput)
        }
        do {
            try await retireReceivingEntries(reservedReceivingEntries)
        } catch {
            throw OpalBase.Account.MosaicHostFailure.reservationCleanupFailed
        }
        reservedInputs.removeAll()
        committedTransaction = requestedTransaction
    }

    func expireMosaicReservation(
        _ reservationReference: OpalFusion.Host.MosaicReservationReference,
        at date: Date
    ) async throws {
        try requireMatchingReference(reservationReference)
        guard let reservationLease,
              date >= reservationLease.expiresAt,
              !isReleased,
              committedTransaction == nil else {
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
