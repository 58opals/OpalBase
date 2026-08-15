// OpalBase+Account+MosaicCompleteTransactionValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
import OpalFusion

extension _OpalBase.Account {
    /// Shared exact proposal/body/signature validation for live and recovered commits.
    enum MosaicCompleteTransactionValidator {
        static func validateProposal(
            _ request: OpalFusion.Host.MosaicTransactionSigningRequest
        ) throws -> (
            transaction: OpalBase.Transaction,
            feeSatoshis: UInt64
        ) {
            guard request.transcriptBinding.matches(
                unsignedTransactionBytes: request.unsignedTransactionBytes
            ) else {
                throw MosaicHostFailure.invalidTransactionProposal
            }
            let transaction = try decodeExactProposal(
                Data(request.unsignedTransactionBytes)
            )
            guard transaction.inputs.count == request.spentInputs.count else {
                throw MosaicHostFailure.invalidTransactionProposal
            }
            try validateInputs(
                transaction.inputs,
                spentInputs: request.spentInputs,
                localInputIndices: Set(request.localInputIndices)
            )
            try validateOutputs(
                transaction.outputs,
                expectedLocalOutputs: request.expectedLocalOutputs
            )
            let inputValue = try sumValues(
                request.spentInputs.map(\.amountSatoshis)
            )
            let outputValue = try sumValues(
                transaction.outputs.map(\.value)
            )
            guard inputValue >= outputValue else {
                throw MosaicHostFailure.invalidTransactionProposal
            }
            return (transaction, inputValue - outputValue)
        }

        static func validateComplete(
            _ completeTransaction: OpalFusion.Host
                .MosaicCompleteTransaction,
            signingRequest: OpalFusion.Host.MosaicTransactionSigningRequest
        ) throws -> OpalBase.Transaction {
            let proposal: OpalBase.Transaction
            do {
                proposal = try validateProposal(signingRequest).transaction
            } catch {
                throw MosaicHostFailure.invalidCompleteTransaction
            }
            let complete = try decodeExactComplete(
                Data(completeTransaction.transactionBytes)
            )
            guard hasSameTransactionBody(complete, as: proposal),
                  complete.inputs.count == signingRequest.spentInputs.count
            else {
                throw MosaicHostFailure.invalidCompleteTransaction
            }
            do {
                for index in complete.inputs.indices {
                    try validateCompleteSignature(
                        transaction: complete,
                        inputIndex: index,
                        spentInput: signingRequest.spentInputs[index]
                    )
                }
            } catch {
                throw MosaicHostFailure.invalidCompleteTransaction
            }
            return complete
        }

        private static func decodeExactProposal(
            _ bytes: Data
        ) throws -> OpalBase.Transaction {
            do {
                let decoded = try OpalBase.Transaction.decode(from: bytes)
                guard decoded.bytesRead == bytes.count,
                      try decoded.transaction.encode() == bytes else {
                    throw MosaicHostFailure.invalidTransactionProposal
                }
                return decoded.transaction
            } catch let failure as MosaicHostFailure {
                throw failure
            } catch {
                throw MosaicHostFailure.invalidTransactionProposal
            }
        }

        private static func decodeExactComplete(
            _ bytes: Data
        ) throws -> OpalBase.Transaction {
            do {
                let decoded = try OpalBase.Transaction.decode(from: bytes)
                guard decoded.bytesRead == bytes.count,
                      try decoded.transaction.encode() == bytes else {
                    throw MosaicHostFailure.invalidCompleteTransaction
                }
                return decoded.transaction
            } catch let failure as MosaicHostFailure {
                throw failure
            } catch {
                throw MosaicHostFailure.invalidCompleteTransaction
            }
        }

        private static func validateInputs(
            _ transactionInputs: [OpalBase.Transaction.Input],
            spentInputs: [OpalFusion.Host.ParticipantInput],
            localInputIndices: Set<Int>
        ) throws {
            for index in transactionInputs.indices {
                let transactionInput = transactionInputs[index]
                let spentInput = spentInputs[index]
                guard transactionInput.unlockingScript.isEmpty,
                      Data(spentInput.outpointTransactionHashBytes)
                        == transactionInput.previousTransactionHash
                            .reverseOrder,
                      spentInput.outpointIndex
                        == transactionInput.previousTransactionOutputIndex,
                      case let .p2pkh_OPCHECKSIG(expectedHash) = try OpalBase
                        .Script.decode(
                            lockingScript: Data(
                                spentInput.lockingScriptBytes
                            )
                        ) else {
                    throw MosaicHostFailure.invalidTransactionProposal
                }
                if let publicKeyBytes = spentInput.publicKey {
                    guard let publicKey = try? OpalBase.Key.PublicKey(
                        compressedData: Data(publicKeyBytes)
                    ),
                          OpalBase.Key.PublicKey.Hash(publicKey: publicKey)
                            == expectedHash else {
                        throw MosaicHostFailure.invalidTransactionProposal
                    }
                } else if localInputIndices.contains(index) {
                    throw MosaicHostFailure.invalidTransactionProposal
                }
                for previousIndex in transactionInputs.indices
                    where previousIndex < index {
                    let previousInput = transactionInputs[previousIndex]
                    guard previousInput.previousTransactionHash
                            != transactionInput.previousTransactionHash
                            || previousInput.previousTransactionOutputIndex
                                != transactionInput
                                    .previousTransactionOutputIndex else {
                        throw MosaicHostFailure.invalidTransactionProposal
                    }
                }
            }
        }

        private static func validateOutputs(
            _ transactionOutputs: [OpalBase.Transaction.Output],
            expectedLocalOutputs: [OpalFusion.Host.ParticipantOutput]
        ) throws {
            for transactionOutput in transactionOutputs {
                guard transactionOutput.tokenData == nil,
                      case .p2pkh_OPCHECKSIG = try OpalBase.Script.decode(
                        lockingScript: transactionOutput.lockingScript
                      ) else {
                    throw MosaicHostFailure.invalidTransactionProposal
                }
            }
            var unmatchedOutputs = transactionOutputs
            for expectedOutput in expectedLocalOutputs {
                guard let index = unmatchedOutputs.firstIndex(where: {
                    $0.value == expectedOutput.amountSatoshis
                        && $0.lockingScript
                            == Data(expectedOutput.lockingScriptBytes)
                        && $0.tokenData == nil
                }) else {
                    throw MosaicHostFailure.invalidTransactionProposal
                }
                unmatchedOutputs.remove(at: index)
            }
        }

        private static func sumValues(
            _ values: [UInt64]
        ) throws -> UInt64 {
            var total: UInt64 = 0
            for value in values {
                let addition = total.addingReportingOverflow(value)
                guard !addition.overflow else {
                    throw MosaicHostFailure.invalidTransactionProposal
                }
                total = addition.partialValue
            }
            return total
        }

        private static func hasSameTransactionBody(
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

        private static func validateCompleteSignature(
            transaction: OpalBase.Transaction,
            inputIndex: Int,
            spentInput: OpalFusion.Host.ParticipantInput
        ) throws {
            let unlockingScript = transaction.inputs[inputIndex]
                .unlockingScript
            let hashType = OpalBase.Transaction.HashType.makeAll(
                anyoneCanPay: false
            )
            guard unlockingScript.count == 100,
                  unlockingScript[0] == 65,
                  unlockingScript[65]
                    == UInt8(truncatingIfNeeded: hashType.value),
                  unlockingScript[66] == 33 else {
                throw MosaicHostFailure.invalidCompleteTransaction
            }
            let publicKeyData = Data(unlockingScript[67 ..< 100])
            guard spentInput.publicKey.map({ Data($0) == publicKeyData })
                    ?? true,
                  let decodedPublicKey = try? OpalBase.Key.PublicKey(
                    compressedData: publicKeyData
                  ),
                  case let .p2pkh_OPCHECKSIG(expectedHash) = try? OpalBase
                    .Script.decode(
                        lockingScript: Data(spentInput.lockingScriptBytes)
                    ),
                  OpalBase.Key.PublicKey.Hash(publicKey: decodedPublicKey)
                    == expectedHash else {
                throw MosaicHostFailure.invalidCompleteTransaction
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
            guard try signature.verify(digest: digest, publicKey: publicKey)
            else {
                throw MosaicHostFailure.invalidCompleteTransaction
            }
        }
    }
}
#endif
