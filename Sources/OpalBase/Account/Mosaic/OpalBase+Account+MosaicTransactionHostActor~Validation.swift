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
              request.transactionProfileIdentifier
                == reservationRequest.transactionProfileIdentifier,
              request.expectedLocalOutputs == reservationLease.participantReservation.outputs else {
            throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        }

        let serializedTransaction = Data(request.unsignedTransactionBytes)
        let decoded: (transaction: OpalBase.Transaction, bytesRead: Int)
        do {
            decoded = try OpalBase.Transaction.decode(from: serializedTransaction)
        } catch {
            throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        }
        guard decoded.bytesRead == serializedTransaction.count,
              decoded.transaction.inputs.count == request.spentInputs.count else {
            throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        }

        try validateInputs(
            decoded.transaction.inputs,
            spentInputs: request.spentInputs
        )
        try validateOutputs(
            decoded.transaction.outputs,
            expectedLocalOutputs: request.expectedLocalOutputs
        )
        let assignments = try makeLocalAssignments(request)
        let inputValue = try sumValues(request.spentInputs.map(\.amountSatoshis))
        let outputValue = try sumValues(decoded.transaction.outputs.map(\.value))
        guard inputValue >= outputValue else {
            throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        }
        return (decoded.transaction, inputValue - outputValue, assignments)
    }

    func validateInputs(
        _ transactionInputs: [OpalBase.Transaction.Input],
        spentInputs: [OpalFusion.Host.ParticipantInput]
    ) throws {
        for index in transactionInputs.indices {
            let transactionInput = transactionInputs[index]
            let spentInput = spentInputs[index]
            guard transactionInput.unlockingScript.isEmpty,
                  Data(spentInput.outpointTransactionHashBytes)
                    == transactionInput.previousTransactionHash.reverseOrder,
                  spentInput.outpointIndex
                    == transactionInput.previousTransactionOutputIndex,
                  let publicKeyBytes = spentInput.publicKey,
                  let publicKey = try? OpalBase.Key.PublicKey(
                    compressedData: Data(publicKeyBytes)
                  ),
                  case .p2pkh_OPCHECKSIG(let expectedHash) = try OpalBase.Script.decode(
                    lockingScript: Data(spentInput.lockingScriptBytes)
                  ),
                  OpalBase.Key.PublicKey.Hash(publicKey: publicKey) == expectedHash else {
                throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
            }
            for previousIndex in transactionInputs.indices where previousIndex < index {
                let previousInput = transactionInputs[previousIndex]
                guard previousInput.previousTransactionHash
                        != transactionInput.previousTransactionHash
                        || previousInput.previousTransactionOutputIndex
                        != transactionInput.previousTransactionOutputIndex else {
                    throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
                }
            }
        }
    }

    func validateOutputs(
        _ transactionOutputs: [OpalBase.Transaction.Output],
        expectedLocalOutputs: [OpalFusion.Host.ParticipantOutput]
    ) throws {
        for transactionOutput in transactionOutputs {
            guard transactionOutput.tokenData == nil,
                  case .p2pkh_OPCHECKSIG = try OpalBase.Script.decode(
                    lockingScript: transactionOutput.lockingScript
                  ) else {
                throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
            }
        }

        var unmatchedOutputs = transactionOutputs
        for expectedOutput in expectedLocalOutputs {
            guard let index = unmatchedOutputs.firstIndex(where: {
                $0.value == expectedOutput.amountSatoshis
                    && $0.lockingScript == Data(expectedOutput.lockingScriptBytes)
                    && $0.tokenData == nil
            }) else {
                throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
            }
            unmatchedOutputs.remove(at: index)
        }
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

    func sumValues(_ values: [UInt64]) throws -> UInt64 {
        var total: UInt64 = 0
        for value in values {
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else {
                throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
            }
            total = addition.partialValue
        }
        return total
    }
}
#endif
