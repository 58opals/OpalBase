// OpalBase+Account+MosaicTransactionHostActor~Signing.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account.MosaicTransactionHostActor {
    func finalizeMosaicTransaction(
        for request: OpalFusion.Host.MosaicTransactionSigningRequest
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        try requireMatchingReference(request.reservationReference)
        guard !releaseStarted, !commitStarted, !isReleased,
              committedCompleteTransaction == nil,
              let reservationLease else {
            throw OpalBase.Account.MosaicHostFailure.terminalReservation
        }
        if currentDate() >= reservationLease.expiresAt {
            try await releaseMosaicReservation(request.reservationReference)
            throw OpalBase.Account.MosaicHostFailure.reservationExpired
        }
        if let finalizedRequest, let finalizedTransaction {
            guard finalizedRequest == request else {
                throw OpalBase.Account.MosaicHostFailure.conflictingFinalization
            }
            if !locallySignedPersisted {
                try await persist(
                    .locallySigned(
                        reference: request.reservationReference,
                        transaction: finalizedTransaction
                    )
                )
                locallySignedPersisted = true
            }
            return finalizedTransaction
        }

        let proposal = try validateTransactionProposal(request)
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

        try await persist(.signingIntent(request))
        var signedTransaction = proposal.transaction
        signingStarted = true
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
            try await persist(
                .locallySigned(
                    reference: request.reservationReference,
                    transaction: finalized
                )
            )
            locallySignedPersisted = true
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
