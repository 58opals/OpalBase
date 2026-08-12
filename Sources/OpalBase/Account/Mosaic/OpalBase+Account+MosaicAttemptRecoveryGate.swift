// OpalBase+Account+MosaicAttemptRecoveryGate.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Re-establishes conservative input quarantine from an authenticated loaded snapshot.
    ///
    /// Key loading, storage, output cleanup, signing, commit, chain reconciliation, approval,
    /// and relay remain app-owned boundaries.
    actor MosaicAttemptRecoveryGate {
        struct RecoveryAuthority: Sendable {
            fileprivate init() {}
        }

        private struct Outpoint: Hashable {
            let transactionHash: Data
            let outputIndex: UInt32

            init(_ input: MosaicAttemptJournal.SelectedInput) {
                transactionHash = input.transactionHash
                outputIndex = input.outputIndex
            }

            init(_ input: OpalBase.Transaction.Output.Unspent) {
                transactionHash = input.previousTransactionHash.naturalOrder
                outputIndex = input.previousTransactionOutputIndex
            }
        }

        let addressBook: OpalBase.Address.Book
        let journal: MosaicAttemptJournal
        private let records: [MosaicAttemptJournal.Record]
        private let plan: MosaicAttemptRecoveryPlanner.Plan
        private var recoveryInFlight = false
        private var outcomeIssued = false

        init(
            addressBook: OpalBase.Address.Book,
            recovery: consuming MosaicAttemptJournalStore.LoadedRecovery
        ) {
            let state = recovery.claim()
            self.addressBook = addressBook
            journal = state.journal
            records = state.records
            plan = state.plan
        }

        func restoreInputQuarantineAndPlan() async throws -> Outcome {
            guard !outcomeIssued else {
                throw Failure.outcomeAlreadyIssued
            }
            guard !recoveryInFlight else {
                throw Failure.recoveryInProgress
            }
            recoveryInFlight = true
            defer { recoveryInFlight = false }

            switch plan {
            case .noAction:
                preconditionFailure(
                    "Loaded recovery cannot contain an empty journal"
                )
            case .released:
                return issue(.released)
            default:
                break
            }

            let everySelectedInputIsPresent = try await quarantineSelectedInputs(
                from: records
            )

            switch plan {
            case .noAction, .released:
                preconditionFailure("Handled before input quarantine")
            case .releaseBeforeSigning,
                 .reconcileSigningIntent,
                 .reconcileLocallySignedTransaction,
                 .finishRelease,
                 .finishCommit:
                return issue(.walletReconciliationRequired(plan))
            case .broadcastApprovalRequired where !everySelectedInputIsPresent:
                return issue(.walletReconciliationRequired(plan))
            case .broadcastApprovalRequired:
                return issue(.broadcastApprovalRequired(
                    try makeBroadcastCandidate(from: records, plan: plan)
                ))
            case .resumeApprovedBroadcast where !everySelectedInputIsPresent:
                return issue(.walletReconciliationRequired(plan))
            case .resumeApprovedBroadcast:
                return issue(.resumeApprovedBroadcast(
                    try makeBroadcastCandidate(from: records, plan: plan)
                ))
            case let .complete(hash):
                return issue(.chainReconciliationRequired(hash))
            }
        }

        private func issue(_ outcome: Outcome) -> Outcome {
            outcomeIssued = true
            return outcome
        }

        private func quarantineSelectedInputs(
            from records: [MosaicAttemptJournal.Record]
        ) async throws -> Bool {
            guard case let .reservationIntent(_, _, selectedInputs, _)?
                    = records.first,
                  !selectedInputs.isEmpty else {
                throw Failure.invalidSelectedInput
            }

            var expectedOutpoints: Set<Outpoint> = []
            for input in selectedInputs {
                guard input.transactionHash.count
                        == OpalBase.Transaction.Hash.expectedByteCount,
                      expectedOutpoints.insert(Outpoint(input)).inserted else {
                    throw Failure.invalidSelectedInput
                }
            }

            try Task.checkCancellation()
            let storedInputs = await addressBook.listUTXOs()
            let spendableInputs = await addressBook.listSpendableUTXOs()
            let storedByOutpoint = Dictionary(
                uniqueKeysWithValues: storedInputs.map { (Outpoint($0), $0) }
            )
            let spendableOutpoints = Set(spendableInputs.map(Outpoint.init))

            var inputsToQuarantine: Set<OpalBase.Transaction.Output.Unspent> = []
            var everySelectedInputIsPresent = true
            for selectedInput in selectedInputs {
                let outpoint = Outpoint(selectedInput)
                guard let storedInput = storedByOutpoint[outpoint] else {
                    everySelectedInputIsPresent = false
                    continue
                }
                guard storedInput.value == selectedInput.amountSatoshis,
                      storedInput.lockingScript == selectedInput.lockingScript,
                      storedInput.tokenData == nil else {
                    throw Failure.selectedInputMismatch
                }
                if spendableOutpoints.contains(outpoint) {
                    inputsToQuarantine.insert(storedInput)
                }
            }

            if !inputsToQuarantine.isEmpty {
                try Task.checkCancellation()
                do {
                    try await addressBook.reserveUTXOs(
                        inputsToQuarantine,
                        tokenSelectionPolicy: .excludeTokenUTXOs
                    )
                } catch let cancellation as CancellationError {
                    throw cancellation
                } catch {
                    throw Failure.inputQuarantineFailed
                }
                try Task.checkCancellation()
            }
            return everySelectedInputIsPresent
        }

        private func makeBroadcastCandidate(
            from records: [MosaicAttemptJournal.Record],
            plan: MosaicAttemptRecoveryPlanner.Plan
        ) throws -> MosaicCommittedBroadcastCandidate {
            guard case let .reservationIntent(
                recordedReference,
                reservationRequest,
                _,
                _
            )? = records.first else {
                throw Failure.invalidBroadcastCandidate
            }

            let reservationReference: OpalFusion.Host.MosaicReservationReference
            let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
            let approvalPersisted: Bool
            let broadcastIntentPersisted: Bool
            switch plan {
            case let .broadcastApprovalRequired(
                reference,
                transaction,
                intentPersisted
            ):
                guard reference == recordedReference else {
                    throw Failure.invalidBroadcastCandidate
                }
                reservationReference = reference
                completeTransaction = transaction
                approvalPersisted = false
                broadcastIntentPersisted = intentPersisted
            case let .resumeApprovedBroadcast(
                reference,
                transaction,
                intentPersisted
            ):
                guard reference == recordedReference else {
                    throw Failure.invalidBroadcastCandidate
                }
                reservationReference = reference
                completeTransaction = transaction
                approvalPersisted = true
                broadcastIntentPersisted = intentPersisted
            default:
                throw Failure.invalidBroadcastCandidate
            }

            do {
                return try .init(
                    recoveryAuthority: .init(),
                    reservationRequest: reservationRequest,
                    reservationReference: reservationReference,
                    completeTransaction: completeTransaction,
                    journal: journal,
                    approvalPersisted: approvalPersisted,
                    broadcastIntentPersisted: broadcastIntentPersisted
                )
            } catch {
                throw Failure.invalidBroadcastCandidate
            }
        }
    }
}
#endif
