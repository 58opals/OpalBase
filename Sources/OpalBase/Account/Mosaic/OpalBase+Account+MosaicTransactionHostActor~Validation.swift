// OpalBase+Account+MosaicTransactionHostActor~Validation.swift

#if os(macOS)
import Foundation
import OpalCrypto
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
            spentInputs: request.spentInputs,
            localInputIndices: Set(request.localInputIndices)
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
        spentInputs: [OpalFusion.Host.ParticipantInput],
        localInputIndices: Set<Int>
    ) throws {
        for index in transactionInputs.indices {
            let transactionInput = transactionInputs[index]
            let spentInput = spentInputs[index]
            guard transactionInput.unlockingScript.isEmpty,
                  Data(spentInput.outpointTransactionHashBytes)
                    == transactionInput.previousTransactionHash.reverseOrder,
                  spentInput.outpointIndex
                    == transactionInput.previousTransactionOutputIndex,
                  case .p2pkh_OPCHECKSIG(let expectedHash) = try OpalBase.Script.decode(
                    lockingScript: Data(spentInput.lockingScriptBytes)
                  ) else {
                throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
            }
            if let publicKeyBytes = spentInput.publicKey {
                guard let publicKey = try? OpalBase.Key.PublicKey(
                    compressedData: Data(publicKeyBytes)
                ), OpalBase.Key.PublicKey.Hash(publicKey: publicKey) == expectedHash else {
                    throw OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
                }
            } else if localInputIndices.contains(index) {
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

    func validateCompleteTransaction(
        _ completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
    ) throws -> OpalBase.Transaction {
        guard let finalizedRequest else {
            throw OpalBase.Account.MosaicHostFailure.finalizationRequired
        }
        let proposal = try validateTransactionProposal(finalizedRequest).transaction
        let encoded = Data(completeTransaction.transactionBytes)
        let decoded: (transaction: OpalBase.Transaction, bytesRead: Int)
        do {
            decoded = try OpalBase.Transaction.decode(from: encoded)
        } catch {
            throw OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction
        }
        guard decoded.bytesRead == encoded.count,
              try decoded.transaction.encode() == encoded,
              hasSameTransactionBody(decoded.transaction, as: proposal),
              decoded.transaction.inputs.count == finalizedRequest.spentInputs.count else {
            throw OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction
        }

        do {
            for index in decoded.transaction.inputs.indices {
                try validateCompleteSignature(
                    transaction: decoded.transaction,
                    inputIndex: index,
                    spentInput: finalizedRequest.spentInputs[index]
                )
            }
        } catch {
            throw OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction
        }
        return decoded.transaction
    }

    private func hasSameTransactionBody(
        _ complete: OpalBase.Transaction,
        as proposal: OpalBase.Transaction
    ) -> Bool {
        guard complete.version == proposal.version,
              complete.lockTime == proposal.lockTime,
              complete.inputs.count == proposal.inputs.count,
              complete.outputs == proposal.outputs else {
            return false
        }
        return complete.inputs.indices.allSatisfy { index in
            let completeInput = complete.inputs[index]
            let proposalInput = proposal.inputs[index]
            return completeInput.previousTransactionHash
                    == proposalInput.previousTransactionHash
                && completeInput.previousTransactionOutputIndex
                    == proposalInput.previousTransactionOutputIndex
                && completeInput.sequence == proposalInput.sequence
        }
    }

    private func validateCompleteSignature(
        transaction: OpalBase.Transaction,
        inputIndex: Int,
        spentInput: OpalFusion.Host.ParticipantInput
    ) throws {
        let unlockingScript = transaction.inputs[inputIndex].unlockingScript
        let hashType = OpalBase.Transaction.HashType.makeAll(
            anyoneCanPay: false
        )
        guard unlockingScript.count == 100,
              unlockingScript[0] == 65,
              unlockingScript[65] == UInt8(truncatingIfNeeded: hashType.value),
              unlockingScript[66] == 33 else {
            throw OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction
        }
        let publicKeyData = Data(unlockingScript[67 ..< 100])
        guard spentInput.publicKey.map({ Data($0) == publicKeyData }) ?? true,
              let decodedPublicKey = try? OpalBase.Key.PublicKey(
                  compressedData: publicKeyData
              ),
              case .p2pkh_OPCHECKSIG(let expectedHash) = try? OpalBase.Script.decode(
                  lockingScript: Data(spentInput.lockingScriptBytes)
              ),
              OpalBase.Key.PublicKey.Hash(publicKey: decodedPublicKey) == expectedHash else {
            throw OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction
        }
        let outputBeingSpent = OpalBase.Transaction.Output(
            value: spentInput.amountSatoshis,
            lockingScript: Data(spentInput.lockingScriptBytes)
        )
        let preimage = try transaction.generatePreimage(
            for: inputIndex,
            hashType: hashType,
            outputBeingSpent: outputBeingSpent
        )
        let signature = try OpalCrypto.Signature.Schnorr(
            rawRepresentation: Data(unlockingScript[1 ..< 65])
        )
        let publicKey = try OpalCrypto.Secp256k1.PublicKey(
            rawRepresentation: publicKeyData
        )
        let digest = try OpalCrypto.Signature.Digest(
            rawRepresentation: OpalCrypto.Hashing.hash256(preimage)
        )
        guard try signature.verify(digest: digest, publicKey: publicKey) else {
            throw OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction
        }
    }
}
#endif
