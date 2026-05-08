#if os(macOS)
// OpalBase+Account+CashFusionTransactionAssembler.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    enum CashFusionTransactionAssemblyError: Swift.Error, Equatable {
        case trailingUnsignedTransactionBytes
        case inputCountMismatch(expected: Int, actual: Int)
        case outputCountMismatch(expected: Int, actual: Int)
        case localInputMismatch
        case duplicatedLocalInput
    }

    struct CashFusionTransactionAssembler: OpalFusion.Host.TransactionAssembler {
        private static let transactionAssemblyFailedSummary = "CashFusion transaction assembly failed"
        private static let hostPolicyRejectedSummary = "CashFusion host policy rejected transaction"

        let reservation: CashFusionReservation

        func finalizeTransaction(
            for roundIdentifier: OpalFusion.Round.Identifier,
            proposal: OpalFusion.Host.TransactionFinalizationProposal
        ) async throws -> OpalFusion.Host.FinalizedTransaction {
            do {
                _ = try await reservation.participantReservation(for: roundIdentifier)
            } catch let error as CancellationError {
                throw error
            } catch {
                throw OpalFusion.Host.TransactionFinalizationFailure.hostPolicyRejected(
                    summary: Self.hostPolicyRejectedSummary
                )
            }

            do {
                let serializedUnsignedTransaction = Data(proposal.unsignedTransactionBytes)
                let decoded = try OpalBase.Transaction.decode(from: serializedUnsignedTransaction)
                guard decoded.bytesRead == serializedUnsignedTransaction.count else {
                    throw CashFusionTransactionAssemblyError.trailingUnsignedTransactionBytes
                }
                if let expectedInputCount = proposal.expectedInputCount,
                   decoded.transaction.inputs.count != expectedInputCount {
                    throw CashFusionTransactionAssemblyError.inputCountMismatch(
                        expected: expectedInputCount,
                        actual: decoded.transaction.inputs.count
                    )
                }
                if let expectedOutputCount = proposal.expectedOutputCount,
                   decoded.transaction.outputs.count != expectedOutputCount {
                    throw CashFusionTransactionAssemblyError.outputCountMismatch(
                        expected: expectedOutputCount,
                        actual: decoded.transaction.outputs.count
                    )
                }

                let inputAssignments = try makeInputAssignments(for: decoded.transaction)
                var finalizedTransaction = decoded.transaction

                for assignment in inputAssignments {
                    finalizedTransaction = try finalizedTransaction.signInputInPlace(
                        at: assignment.transactionInputIndex,
                        spending: assignment.reservedInput.unspentOutput,
                        privateKey: assignment.reservedInput.privateKey,
                        signatureFormat: OpalBase.Transaction.SignatureFormat.schnorr,
                        unlocker: OpalBase.Transaction.Unlocker.p2pkh_CheckSig(),
                        using: decoded.transaction
                    )
                }

                return .init(
                    transactionBytes: [UInt8](try finalizedTransaction.encode())
                )
            } catch let error as CancellationError {
                throw error
            } catch {
                throw OpalFusion.Host.TransactionFinalizationFailure.transactionAssemblyFailed(
                    summary: Self.transactionAssemblyFailedSummary
                )
            }
        }

        private func makeInputAssignments(
            for transaction: OpalBase.Transaction
        ) throws -> [(transactionInputIndex: Int, reservedInput: CashFusionReservation.ReservedInput)] {
            var reservedInputByOutpoint: [Outpoint: CashFusionReservation.ReservedInput] = [:]
            reservedInputByOutpoint.reserveCapacity(reservation.reservedInputs.count)

            for reservedInput in reservation.reservedInputs {
                if reservedInputByOutpoint.updateValue(
                    reservedInput,
                    forKey: Outpoint(reservedInput.unspentOutput)
                ) != nil {
                    throw CashFusionTransactionAssemblyError.duplicatedLocalInput
                }
            }

            var matchedOutpoints: Set<Outpoint> = []
            matchedOutpoints.reserveCapacity(reservation.reservedInputs.count)
            var assignments: [(transactionInputIndex: Int, reservedInput: CashFusionReservation.ReservedInput)] = []
            assignments.reserveCapacity(reservation.reservedInputs.count)

            for element in transaction.inputs.enumerated() {
                let index = element.offset
                let outpoint = Outpoint(element.element)
                guard let reservedInput = reservedInputByOutpoint[outpoint] else {
                    continue
                }
                guard matchedOutpoints.insert(outpoint).inserted else {
                    throw CashFusionTransactionAssemblyError.duplicatedLocalInput
                }
                assignments.append(
                    (transactionInputIndex: index, reservedInput: reservedInput)
                )
            }

            guard assignments.count == reservation.reservedInputs.count else {
                throw CashFusionTransactionAssemblyError.localInputMismatch
            }

            return assignments
        }
    }
}

private extension _OpalBase.Account.CashFusionTransactionAssembler {
    struct Outpoint: Hashable, Sendable {
        let transactionHash: OpalBase.Transaction.Hash
        let outputIndex: UInt32

        init(_ input: OpalBase.Transaction.Input) {
            self.transactionHash = input.previousTransactionHash
            self.outputIndex = input.previousTransactionOutputIndex
        }

        init(_ unspentOutput: OpalBase.Transaction.Output.Unspent) {
            self.transactionHash = unspentOutput.previousTransactionHash
            self.outputIndex = unspentOutput.previousTransactionOutputIndex
        }
    }
}
#endif
