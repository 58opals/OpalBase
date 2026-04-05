// OpalBase+Account+CashFusionTransactionAssembler.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    enum CashFusionTransactionAssemblyError: Swift.Error, Equatable {
        case trailingUnsignedTransactionBytes
        case localInputMismatch
        case localInputOrderMismatch
    }

    struct CashFusionTransactionAssembler: OpalFusion.Host.TransactionAssembler {
        let reservation: CashFusionReservation

        func finalizeTransaction(
            for roundIdentifier: OpalFusion.Round.Identifier,
            proposal: OpalFusion.Host.TransactionFinalizationProposal
        ) async throws -> OpalFusion.Host.FinalizedTransaction {
            _ = roundIdentifier

            let serializedUnsignedTransaction = Data(proposal.serializedUnsignedTransaction)
            let decoded = try OpalBase.Transaction.decode(from: serializedUnsignedTransaction)
            guard decoded.bytesRead == serializedUnsignedTransaction.count else {
                throw CashFusionTransactionAssemblyError.trailingUnsignedTransactionBytes
            }

            let inputAssignments = try makeInputAssignments(for: decoded.transaction)
            var finalizedTransaction = decoded.transaction

            for assignment in inputAssignments {
                finalizedTransaction = try finalizedTransaction.signInputInPlace(
                    at: assignment.transactionInputIndex,
                    spending: assignment.reservedInput.unspentOutput,
                    privateKey: assignment.reservedInput.privateKey,
                    signatureFormat: .schnorr,
                    unlocker: .p2pkh_CheckSig(),
                    using: decoded.transaction
                )
            }

            return .init(
                serializedTransaction: [UInt8](try finalizedTransaction.encode())
            )
        }

        private func makeInputAssignments(
            for transaction: OpalBase.Transaction
        ) throws -> [(transactionInputIndex: Int, reservedInput: CashFusionReservation.ReservedInput)] {
            let reservedInputByOutpoint = Dictionary(
                uniqueKeysWithValues: reservation.reservedInputs.map {
                    (Outpoint($0.unspentOutput), $0)
                }
            )

            var assignments: [(transactionInputIndex: Int, reservedInput: CashFusionReservation.ReservedInput)] = []
            assignments.reserveCapacity(reservation.reservedInputs.count)

            for element in transaction.inputs.enumerated() {
                let index = element.offset
                let outpoint = Outpoint(element.element)
                guard let reservedInput = reservedInputByOutpoint[outpoint] else {
                    continue
                }
                assignments.append(
                    (transactionInputIndex: index, reservedInput: reservedInput)
                )
            }

            guard assignments.count == reservation.reservedInputs.count else {
                throw CashFusionTransactionAssemblyError.localInputMismatch
            }

            let assignedOutpoints = assignments.map { Outpoint($0.reservedInput.unspentOutput) }
            let reservedOutpoints = reservation.reservedInputs.map {
                Outpoint($0.unspentOutput)
            }
            guard assignedOutpoints == reservedOutpoints else {
                throw CashFusionTransactionAssemblyError.localInputOrderMismatch
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
