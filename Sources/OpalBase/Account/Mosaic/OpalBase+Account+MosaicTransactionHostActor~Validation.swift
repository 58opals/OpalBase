// OpalBase+Account+MosaicTransactionHostActor~Validation.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account.MosaicTransactionHostActor {
    func validateTransactionProposal(
        _ request: OpalFusion.Host.MosaicTransactionSigningRequest
    ) throws -> (
        transaction: OpalBase.Transaction,
        feeSatoshis: UInt64,
        assignments: [(index: Int, record: OpalBase.Account.MosaicReservedInputRecord)]
    ) {
        guard let reservationRequest, let reservationLease,
              request.reservationReference == reservationLease.reference,
              request.roundIdentifier == reservationRequest.roundIdentifier,
              request.feeRateSatoshisPerByte == reservationRequest.feeRateSatoshisPerByte,
              request.minimumExcessFeeSatoshis == reservationRequest.minimumExcessFeeSatoshis,
              request.maximumExcessFeeSatoshis == reservationRequest.maximumExcessFeeSatoshis,
              request.requiredExcessFeeSatoshis
                == reservationRequest.requiredExcessFeeSatoshis,
              request.transcriptBinding.profile == profile,
              request.transactionProfileIdentifier
                == reservationRequest.transactionProfileIdentifier,
              request.transactionProfileIdentifier
                == profile.transactionProfileIdentifier,
              profile.networkGenesisHash == expectedNetworkGenesisHash,
              request.transcriptBinding.matches(
                unsignedTransactionBytes: request.unsignedTransactionBytes
              ),
              request.expectedLocalOutputs == reservationLease.participantReservation.outputs else {
            throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        }

        let validated = try OpalBase.Account
            .MosaicCompleteTransactionValidator.validateProposal(request)
        let assignments = try makeLocalAssignments(request)
        return (
            validated.transaction,
            validated.feeSatoshis,
            assignments
        )
    }

    func makeLocalAssignments(
        _ request: OpalFusion.Host.MosaicTransactionSigningRequest
    ) throws -> [(index: Int, record: OpalBase.Account.MosaicReservedInputRecord)] {
        guard request.localInputIndices.count == reservedInputs.count else {
            throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        }
        var unmatchedRecords = reservedInputs
        var assignments: [(
            index: Int,
            record: OpalBase.Account.MosaicReservedInputRecord
        )] = []

        for inputIndex in request.localInputIndices {
            let participantInput = request.spentInputs[inputIndex]
            guard let recordIndex = unmatchedRecords.firstIndex(where: {
                $0.participantInput == participantInput
            }) else {
                throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
            }
            assignments.append((inputIndex, unmatchedRecords.remove(at: recordIndex)))
        }
        guard unmatchedRecords.isEmpty else {
            throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        }
        return assignments
    }

    func validateCompleteTransaction(
        _ completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
    ) throws -> OpalBase.Transaction {
        guard let finalizedRequest else {
            throw OpalBase.Account.MosaicHostFailure.finalizationRequired
        }
        _ = try validateTransactionProposal(finalizedRequest)
        return try OpalBase.Account.MosaicCompleteTransactionValidator
            .validateComplete(
                completeTransaction,
                signingRequest: finalizedRequest
            )
    }
}
#endif
