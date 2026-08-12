// OpalBase+Account+MosaicTransactionHostActor~Signing.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account.MosaicTransactionHostActor {
    func finalizeMosaicTransaction(
        for request: OpalFusion.Host.MosaicTransactionSigningRequest
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        try requireMatchingReference(request.reservationReference)
        guard let reservationLease else {
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        }
        switch lifecycle {
        case .commitPending, .commitIntentPersisting, .commitRecovery,
             .committing, .committed, .releaseIntent, .released:
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        case .idle, .reservationIntent, .reserved, .finalizationPending,
             .validating, .signingIntent, .localSignaturePending,
             .localSignaturePersisting, .locallySigned:
            break
        }
        if currentDate() >= reservationLease.expiresAt {
            try await releaseMosaicReservation(request.reservationReference)
            throw OpalBase.Account.MosaicHostFailure.reservationExpired
        }
        switch lifecycle {
        case .localSignaturePending:
            guard let finalizedRequest, let finalizedTransaction else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard finalizedRequest == request else {
                throw OpalBase.Account.MosaicHostFailure.conflictingFinalization
            }
            lifecycle = .localSignaturePersisting
            do {
                try await persist(
                    .locallySigned(
                        reference: request.reservationReference,
                        transaction: finalizedTransaction
                    )
                )
            } catch {
                lifecycle = .localSignaturePending
                throw error
            }
            lifecycle = .locallySigned
            return finalizedTransaction
        case .localSignaturePersisting:
            guard let finalizedRequest else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard finalizedRequest == request else {
                throw OpalBase.Account.MosaicHostFailure.conflictingFinalization
            }
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        case .locallySigned:
            guard let finalizedRequest, let finalizedTransaction else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard finalizedRequest == request else {
                throw OpalBase.Account.MosaicHostFailure.conflictingFinalization
            }
            return finalizedTransaction
        case .finalizationPending:
            guard let pendingFinalizationRequest else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard pendingFinalizationRequest == request else {
                throw OpalBase.Account.MosaicHostFailure.conflictingFinalization
            }
        case .reserved:
            pendingFinalizationRequest = request
            lifecycle = .finalizationPending
        case .validating, .signingIntent:
            guard let pendingFinalizationRequest else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
            guard pendingFinalizationRequest == request else {
                throw OpalBase.Account.MosaicHostFailure.conflictingFinalization
            }
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        case .idle, .reservationIntent:
            throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
        case .commitPending, .commitIntentPersisting, .commitRecovery,
             .committing, .committed, .releaseIntent, .released:
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        }

        lifecycle = .validating
        let proposal: (
            transaction: OpalBase.Transaction,
            feeSatoshis: UInt64,
            assignments: [(
                index: Int,
                record: OpalBase.Account.MosaicReservedInputRecord
            )]
        )
        do {
            proposal = try validateTransactionProposal(request)
            do {
                try await transactionPolicy.validate(
                    transaction: proposal.transaction,
                    request: request,
                    feeSatoshis: proposal.feeSatoshis
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw OpalBase.Account.MosaicHostFailure.transactionPolicyRejected
            }

            try Task.checkCancellation()
            if currentDate() >= reservationLease.expiresAt {
                lifecycle = .finalizationPending
                try await releaseMosaicReservation(request.reservationReference)
                throw OpalBase.Account.MosaicHostFailure.reservationExpired
            }
        } catch {
            if lifecycle == .validating {
                lifecycle = .finalizationPending
            }
            throw error
        }

        lifecycle = .signingIntent
        try await persist(.signingIntent(request))
        try Task.checkCancellation()
        guard currentDate() < reservationLease.expiresAt else {
            throw OpalBase.Account.MosaicHostFailure.reservationExpired
        }
        var signedTransaction = proposal.transaction
        do {
            for assignment in proposal.assignments.sorted(by: { $0.index < $1.index }) {
                signingInvocationCount += 1
                signedTransaction = try signedTransaction.signInputInPlace(
                    at: assignment.index,
                    spending: assignment.record.unspentOutput,
                    signingKey: assignment.record.signingKey,
                    signatureFormat: .schnorr,
                    unlocker: .p2pkh_CheckSig(
                        hashType: .makeAll(anyoneCanPay: false)
                    ),
                    using: proposal.transaction
                )
            }
            let finalized = OpalFusion.Host.FinalizedTransaction(
                signedFusionTransactionBytes: [UInt8](try signedTransaction.encode())
            )
            finalizedRequest = request
            finalizedTransaction = finalized
            lifecycle = .localSignaturePersisting
            do {
                try await persist(
                    .locallySigned(
                        reference: request.reservationReference,
                        transaction: finalized
                    )
                )
            } catch {
                lifecycle = .localSignaturePending
                throw error
            }
            lifecycle = .locallySigned
            return finalized
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch let hostFailure as OpalBase.Account.MosaicHostFailure {
            throw hostFailure
        } catch {
            throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        }
    }
}
#endif
