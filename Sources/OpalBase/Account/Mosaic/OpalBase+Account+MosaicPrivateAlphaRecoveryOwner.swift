// OpalBase+Account+MosaicPrivateAlphaRecoveryOwner.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Sole package owner for executing authenticated wallet and chain recovery.
    actor MosaicPrivateAlphaRecoveryOwner:
        OpalFusion.Host.MosaicCompleteTransactionHost {
        let addressBook: OpalBase.Address.Book
        let binding: MosaicAttemptBinding
        let journal: MosaicAttemptJournal

        private var records: [MosaicAttemptJournal.Record]
        private var plan: MosaicAttemptRecoveryPlanner.Plan
        private var lifecycle = Lifecycle.ready
        private var issuedOutcome: Outcome?

        private struct BroadcastContext {
            let reference: OpalFusion.Host.MosaicReservationReference
            let completeTransaction: OpalFusion.Host
                .MosaicCompleteTransaction
            let exactTransaction: MosaicExactTransaction
            let approvalPersisted: Bool
            let intentPersisted: Bool
            let approvalRequest: MosaicTransactionBroadcastCoordinator
                .ApprovalRequest
        }

        init(
            addressBook: OpalBase.Address.Book,
            recovery: consuming MosaicAttemptJournalStore.LoadedRecovery
        ) throws {
            try self.init(addressBook: addressBook, state: recovery.claim())
        }

        init(
            addressBook: OpalBase.Address.Book,
            state: MosaicAttemptJournalStore.RecoveryState
        ) throws {
            do {
                try MosaicAttemptRecoveryPlanner.requirePrivateAlphaProfile(
                    for: state.records
                )
            } catch MosaicAttemptRecoveryPlanner.Error
                .unsupportedPrivateAlphaProfile {
                throw Failure.invalidNetworkBinding
            } catch {
                throw Failure.invalidRecoveryState
            }
            self.addressBook = addressBook
            binding = state.binding
            journal = state.journal
            records = state.records
            plan = state.plan
        }

        /// Reinstates the exact restart quarantine without advancing recovery.
        func prepareForDeterministicReplay() async throws {
            try await restoreExactQuarantine()
        }

        /// Restores quarantine and executes every deterministic wallet recovery step.
        func resume() async throws -> Outcome {
            if let issuedOutcome { return issuedOutcome }
            try beginOperation()
            do {
                let outcome = try await executeCurrentPlan()
                finishOperation(with: outcome)
                return outcome
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Replays only the exact authenticated lease; it never reserves wallet state again.
        func reserveMosaicContribution(
            for request: OpalFusion.Host.MosaicReservationRequest
        ) async throws -> OpalFusion.Host.MosaicReservationLease {
            try requireReplayReadAvailable()
            guard let recordedRequest = recordedReservationRequest,
                  recordedRequest == request else {
                throw MosaicHostFailure.inPlaceRetryNotPermitted
            }
            guard let lease = recordedReservationLease,
                  lease.reference == binding.walletReservationReference else {
                throw MosaicHostFailure.reconciliationRequired
            }
            return lease
        }

        /// Replays recorded local signatures or durably aborts a recovered signing intent.
        func finalizeMosaicTransaction(
            for request: OpalFusion.Host.MosaicTransactionSigningRequest
        ) async throws -> OpalFusion.Host.FinalizedTransaction {
            try requireReplayReadAvailable()
            try requireMatchingReplayReference(request.reservationReference)
            guard recordedSigningRequest == request else {
                throw MosaicHostFailure.conflictingFinalization
            }
            if let transaction = recordedLocallySignedTransaction {
                return transaction
            }

            try requireReplayMutationAvailable()
            try beginOperation()
            issuedOutcome = nil
            do {
                let outcome = try await executeReplayReleasePlan()
                finishOperation(with: outcome)
                throw MosaicHostFailure.reconciliationRequired
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Releases only the exact authenticated wallet plan and is idempotent after wallet release.
        func releaseMosaicReservation(
            _ reservationReference: OpalFusion.Host.MosaicReservationReference
        ) async throws {
            try requireMatchingReplayReference(reservationReference)
            if lifecycle == .terminal,
               case .terminal(.walletReleased) = plan {
                return
            }
            try requireReplayMutationAvailable()
            try beginOperation()
            issuedOutcome = nil
            do {
                let outcome = try await executeReplayReleasePlan()
                finishOperation(with: outcome)
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// The finalized-only callback can prove a no-effect replay only after exact commit.
        func commitMosaicReservation(
            _ reservationReference: OpalFusion.Host.MosaicReservationReference,
            finalizedTransaction: OpalFusion.Host.FinalizedTransaction
        ) async throws {
            try requireReplayReadAvailable()
            try requireMatchingReplayReference(reservationReference)
            guard recordedLocallySignedTransaction == finalizedTransaction,
                  recordedCompleteTransaction != nil,
                  planHasCommittedWalletDisposition else {
                throw MosaicHostFailure.completeTransactionRequired
            }
            if lifecycle == .terminal {
                try await requireCommittedWalletState()
                return
            }
            try beginOperation()
            do {
                try await requireCommittedWalletState()
                lifecycle = .ready
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Commits only the exact complete continuation with write-ahead and exact replay checks.
        func commitMosaicReservation(
            _ reservationReference: OpalFusion.Host.MosaicReservationReference,
            completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        ) async throws {
            try requireReplayReadAvailable()
            try requireMatchingReplayReference(reservationReference)

            switch plan {
            case let .reconcileLocallySignedTransaction(
                expectedReference,
                locallySignedTransaction
            ):
                guard expectedReference == reservationReference,
                      let signingRequest = recordedSigningRequest else {
                    throw MosaicHostFailure.reconciliationRequired
                }
                do {
                    try MosaicExactTransaction
                        .validateLocallySignedContinuation(
                            completeTransaction,
                            from: locallySignedTransaction,
                            signingRequest: signingRequest
                        )
                } catch {
                    throw MosaicHostFailure.invalidCompleteTransaction
                }
            case let .finishCommit(expectedReference, expectedTransaction):
                guard expectedReference == reservationReference else {
                    throw MosaicHostFailure.staleReservationReference
                }
                guard expectedTransaction == completeTransaction else {
                    throw MosaicHostFailure.conflictingCompleteTransaction
                }
            default:
                guard planHasCommittedWalletDisposition,
                      recordedCompleteTransaction == completeTransaction else {
                    if recordedCompleteTransaction != nil {
                        throw MosaicHostFailure
                            .conflictingCompleteTransaction
                    }
                    throw MosaicHostFailure.finalizationRequired
                }
            }

            if lifecycle == .terminal {
                try await requireCommittedWalletState()
                return
            }

            try requireReplayMutationAvailable()
            try beginOperation()
            issuedOutcome = nil
            do {
                switch plan {
                case .reconcileLocallySignedTransaction:
                    try await requireExactInputsPresentForCommit()
                    try await append(
                        .commitIntent(
                            reference: reservationReference,
                            transaction: completeTransaction
                        )
                    )
                    try await finishReplayCommit(
                        reference: reservationReference,
                        transaction: completeTransaction
                    )
                case .finishCommit:
                    try await finishReplayCommit(
                        reference: reservationReference,
                        transaction: completeTransaction
                    )
                default:
                    try await requireCommittedWalletState()
                    lifecycle = .ready
                }
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Continues only the exact locally signed bytes recovered from the journal.
        func commitRecoveredLocallySignedTransaction(
            _ completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        ) async throws -> Outcome {
            try beginOperation()
            issuedOutcome = nil
            do {
                guard case let .reconcileLocallySignedTransaction(
                    reference,
                    locallySignedTransaction
                ) = plan,
                      let signingRequest = recordedSigningRequest else {
                    throw Failure.invalidRecoveryState
                }
                try MosaicExactTransaction.validateLocallySignedContinuation(
                    completeTransaction,
                    from: locallySignedTransaction,
                    signingRequest: signingRequest
                )
                try await requireExactInputsPresentForCommit()
                try await append(
                    .commitIntent(
                        reference: reference,
                        transaction: completeTransaction
                    )
                )
                try await commitWalletState()
                try await append(
                    .committed(
                        reference: reference,
                        transaction: completeTransaction
                    )
                )
                let outcome = try await executeCurrentPlan()
                finishOperation(with: outcome)
                return outcome
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Records one uncached exact chain observation; unknown and mismatched results are not journaled.
        func reconcileChain(
            using transactionClient: MosaicNetworkAttestedTransactionClient
        ) async throws -> ChainOutcome {
            try beginOperation()
            issuedOutcome = nil
            do {
                guard case let .reconcileChain(chainState) = plan else {
                    throw Failure.invalidRecoveryState
                }
                guard let reservationRequest = recordedReservationRequest,
                      let profile = recordedProfile,
                      transactionClient.network.supportsMosaicProfile(
                        profile
                      ),
                      reservationRequest.networkGenesisHash
                        == transactionClient.network.mosaicGenesisHash else {
                    throw Failure.invalidNetworkBinding
                }
                let exactTransaction = try MosaicExactTransaction(
                    chainState.transaction
                )
                let presence = try await transactionClient.presence(
                    of: exactTransaction
                )
                let observation: MosaicAttemptChainObservation
                switch presence {
                case let .present(present):
                    guard let value = MosaicAttemptChainObservation(
                        transactionHash: present.transactionHash,
                        presence: .present(
                            blockHash: present.blockHash,
                            confirmations: present.confirmations
                        )
                    ) else {
                        throw Failure.invalidRecoveryState
                    }
                    observation = value
                case .authoritativeAbsence:
                    guard let value = MosaicAttemptChainObservation(
                        transactionHash: chainState.transactionHash,
                        presence: .authoritativeAbsence
                    ) else {
                        throw Failure.invalidRecoveryState
                    }
                    observation = value
                case let .unknown(reason):
                    lifecycle = .ready
                    return .heldUnknown(reason)
                }
                if chainState.latestObservation == observation {
                    lifecycle = .ready
                    return .observed(chainState)
                }
                try await append(
                    .chainObservation(
                        reference: chainState.reference,
                        transaction: chainState.transaction,
                        observation: observation
                    )
                )
                guard case let .reconcileChain(updatedState) = plan else {
                    throw Failure.invalidRecoveryState
                }
                lifecycle = .ready
                return .observed(updatedState)
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Loads the exact recovered approval context without approving, journaling, or dispatching.
        func loadBroadcastApprovalRequest(
            using transactionClient: MosaicNetworkAttestedTransactionClient
        ) async throws -> MosaicTransactionBroadcastCoordinator
            .ApprovalRequest {
            try beginOperation()
            do {
                let context = try await makeBroadcastContext(
                    using: transactionClient
                )
                lifecycle = .ready
                return context.approvalRequest
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Resumes one approved transaction with write-ahead, exact-presence reconciliation.
        func broadcastRecoveredTransaction(
            securityProfile: OpalBase.WalletSecurityProfile,
            using transactionClient: MosaicNetworkAttestedTransactionClient,
            requestApproval: @escaping MosaicTransactionBroadcastCoordinator
                .RequestApproval
        ) async throws -> MosaicAttemptChainState {
            try beginOperation()
            issuedOutcome = nil
            do {
                try securityProfile.requireBroadcastingAllowed()
                let context = try await makeBroadcastContext(
                    using: transactionClient
                )
                let reference = context.reference
                let completeTransaction = context.completeTransaction
                let exactTransaction = context.exactTransaction
                var approvalPersisted = context.approvalPersisted
                var intentPersisted = context.intentPersisted

                if !approvalPersisted {
                    let decision: MosaicTransactionBroadcastCoordinator
                        .ApprovalDecision
                    do {
                        decision = try await requestApproval(
                            context.approvalRequest
                        )
                    } catch let cancellation as CancellationError {
                        throw cancellation
                    } catch {
                        throw Failure.broadcastNotApproved
                    }
                    guard decision == .approved else {
                        throw Failure.broadcastNotApproved
                    }
                    try await append(
                        .broadcastApproved(
                            reference: reference,
                            transaction: completeTransaction
                        )
                    )
                    approvalPersisted = true
                }

                if intentPersisted {
                    switch try await transactionClient.presence(
                        of: exactTransaction
                    ) {
                    case let .present(observation):
                        try await append(
                            .broadcastAccepted(
                                reference: reference,
                                transaction: completeTransaction,
                                transactionHash: observation.transactionHash
                            )
                        )
                        guard case let .reconcileChain(chainState) = plan else {
                            throw Failure.invalidRecoveryState
                        }
                        let outcome = Outcome
                            .chainReconciliationRequired(chainState)
                        finishOperation(with: outcome)
                        return chainState
                    case .authoritativeAbsence:
                        break
                    case .unknown:
                        throw Failure.broadcastReconciliationRequired
                    }
                } else {
                    try await append(
                        .broadcastIntent(
                            reference: reference,
                            transaction: completeTransaction
                        )
                    )
                    intentPersisted = true
                }

                let transactionHash = try await transactionClient.broadcast(
                    transaction: exactTransaction.transaction
                )
                guard transactionHash == exactTransaction.hash else {
                    throw Failure.broadcastReconciliationRequired
                }
                try await append(
                    .broadcastAccepted(
                        reference: reference,
                        transaction: completeTransaction,
                        transactionHash: transactionHash
                    )
                )
                guard case let .reconcileChain(chainState) = plan else {
                    throw Failure.invalidRecoveryState
                }
                let outcome = Outcome.chainReconciliationRequired(chainState)
                finishOperation(with: outcome)
                return chainState
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Lets the app-owned finality policy authorize only the latest exact chain identity.
        func authorizeChainFinality(
            using authorize: @Sendable (
                MosaicAttemptChainState
            ) async throws -> Bool
        ) async throws -> MosaicAttemptTerminalDisposition {
            try beginOperation()
            issuedOutcome = nil
            do {
                guard case let .reconcileChain(chainState) = plan,
                      let confirmed = chainState.latestObservation?
                        .confirmedIdentity else {
                    throw Failure.terminalDispositionRequired
                }
                guard try await authorize(chainState) else {
                    throw Failure.finalityNotAuthorized
                }
                let disposition = MosaicAttemptTerminalDisposition
                    .chainFinalized(
                        transactionHash: chainState.transactionHash,
                        blockHash: confirmed.blockHash,
                        confirmations: confirmed.confirmations
                    )
                try await append(
                    .terminalDisposition(
                        reference: chainState.reference,
                        transaction: chainState.transaction,
                        disposition: disposition
                    )
                )
                await releaseExactQuarantine(
                    ownedBy: chainState.reference
                )
                lifecycle = .terminal
                issuedOutcome = .terminal(disposition)
                return disposition
            } catch {
                resetOperationAfterFailure()
                throw error
            }
        }

        /// Commits exact-envelope erasure authority; physical cleanup remains app-owned.
        func authorizeJournalErasure() async throws
            -> MosaicAttemptJournalCleanupRequirement {
            switch lifecycle {
            case .terminal:
                lifecycle = .erasureAuthorizing
            case .erasureAuthorizing, .performing:
                throw Failure.operationInProgress
            case .erasureAuthorized:
                throw Failure.erasureAlreadyAuthorized
            case .ready:
                throw Failure.terminalDispositionRequired
            }
            do {
                let authorization = try await journal
                    .authorizeTerminalDisposition()
                let requirement = try await authorization
                    .authorizeJournalErasure()
                lifecycle = .erasureAuthorized
                issuedOutcome = nil
                return requirement
            } catch {
                lifecycle = .terminal
                throw error
            }
        }

        private func executeCurrentPlan() async throws -> Outcome {
            try await restoreExactQuarantine()
            switch plan {
            case .noAction:
                throw Failure.invalidRecoveryState
            case let .walletReconciliationHeld(reference):
                return .walletReconciliationHeld(reference)
            case let .releaseBeforeSigning(reference),
                 let .reconcileSigningIntent(reference, _):
                try await append(.releaseIntent(reference))
                try await releaseWalletState()
                try await append(.released(reference))
                return try await finalizeWalletRelease(reference)
            case let .finishRelease(reference):
                try await releaseWalletState()
                try await append(.released(reference))
                return try await finalizeWalletRelease(reference)
            case .released:
                try await releaseWalletState()
                return try await finalizeWalletRelease(
                    binding.walletReservationReference
                )
            case let .reconcileLocallySignedTransaction(
                reference,
                transaction
            ):
                return .locallySignedContinuation(
                    reference: reference,
                    transaction: transaction
                )
            case let .finishCommit(reference, transaction):
                try await commitWalletState()
                try await append(
                    .committed(
                        reference: reference,
                        transaction: transaction
                    )
                )
                return try makeBroadcastOutcome()
            case .broadcastApprovalRequired, .resumeApprovedBroadcast:
                try await requireCommittedWalletState()
                return try makeBroadcastOutcome()
            case .broadcastReconciliationHeld:
                return .broadcastReconciliationHeld
            case let .reconcileChain(chainState):
                try await requireCommittedWalletState()
                return .chainReconciliationRequired(chainState)
            case let .terminal(disposition):
                await releaseExactQuarantine(
                    ownedBy: binding.walletReservationReference
                )
                return .terminal(disposition)
            }
        }

        private func executeReplayReleasePlan() async throws -> Outcome {
            try await restoreExactQuarantine()
            let expectedReference = binding.walletReservationReference
            switch plan {
            case let .releaseBeforeSigning(reference),
                 let .reconcileSigningIntent(reference, _):
                guard reference == expectedReference else {
                    throw MosaicHostFailure.staleReservationReference
                }
                try await append(.releaseIntent(reference))
                try await releaseWalletState()
                try await append(.released(reference))
                return try await finalizeWalletRelease(reference)
            case let .finishRelease(reference):
                guard reference == expectedReference else {
                    throw MosaicHostFailure.staleReservationReference
                }
                try await releaseWalletState()
                try await append(.released(reference))
                return try await finalizeWalletRelease(reference)
            case .released:
                try await releaseWalletState()
                return try await finalizeWalletRelease(expectedReference)
            case let .terminal(disposition) where disposition == .walletReleased:
                await releaseExactQuarantine(ownedBy: expectedReference)
                return .terminal(disposition)
            default:
                if planHasCommittedWalletDisposition {
                    throw MosaicHostFailure.terminalReservation
                }
                throw MosaicHostFailure.reconciliationRequired
            }
        }

        private func finishReplayCommit(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction
        ) async throws {
            try await commitWalletState()
            try await append(
                .committed(
                    reference: reference,
                    transaction: transaction
                )
            )
            lifecycle = .ready
        }

        private func finalizeWalletRelease(
            _ reference: OpalFusion.Host.MosaicReservationReference
        ) async throws -> Outcome {
            let disposition = MosaicAttemptTerminalDisposition.walletReleased
            try await append(
                .terminalDisposition(
                    reference: reference,
                    transaction: nil,
                    disposition: disposition
                )
            )
            await releaseExactQuarantine(ownedBy: reference)
            return .terminal(disposition)
        }

        private func append(
            _ record: MosaicAttemptJournal.Record
        ) async throws {
            try await journal.append(record)
            records.append(record)
            plan = try MosaicAttemptRecoveryPlanner.plan(for: records)
        }

        private func restoreExactQuarantine() async throws {
            guard let selectedInputs = recordedSelectedInputs else { return }
            await addressBook.quarantineMosaicInputs(
                selectedInputs,
                ownedBy: binding.walletReservationReference
            )
        }

        private func releaseExactQuarantine(
            ownedBy reference: OpalFusion.Host.MosaicReservationReference
        ) async {
            await addressBook.releaseMosaicInputQuarantine(
                ownedBy: reference
            )
        }

        private func releaseWalletState() async throws {
            guard let selectedInputs = recordedSelectedInputs else { return }
            let storedInputs = try await exactStoredInputs(
                matching: selectedInputs,
                absenceAllowed: false
            )
            await addressBook.releaseUTXOs(Set(storedInputs))
            try await retireRecordedReceivingEntries()

            guard !(await addressBook.hasReservedMosaicInputs(storedInputs))
            else {
                throw Failure.walletCleanupIncomplete
            }
            try await requireRecordedReceivingEntriesRetired()
        }

        private func commitWalletState() async throws {
            guard let selectedInputs = recordedSelectedInputs else {
                throw Failure.invalidRecoveryState
            }
            let storedInputs = try await exactStoredInputs(
                matching: selectedInputs,
                absenceAllowed: false
            )
            for input in storedInputs {
                await addressBook.removeUTXO(input)
            }
            try await retireRecordedReceivingEntries()
            try await requireCommittedWalletState()
        }

        private func requireExactInputsPresentForCommit() async throws {
            guard let selectedInputs = recordedSelectedInputs else {
                throw Failure.invalidRecoveryState
            }
            _ = try await exactStoredInputs(
                matching: selectedInputs,
                absenceAllowed: false
            )
        }

        private func requireCommittedWalletState() async throws {
            guard let selectedInputs = recordedSelectedInputs else {
                throw Failure.invalidRecoveryState
            }
            _ = try await exactStoredInputs(
                matching: selectedInputs,
                absenceAllowed: true,
                requireEveryInputAbsent: true
            )
            try await requireRecordedReceivingEntriesRetired()
        }

        private func exactStoredInputs(
            matching selectedInputs: [MosaicAttemptJournal.SelectedInput],
            absenceAllowed: Bool,
            requireEveryInputAbsent: Bool = false
        ) async throws -> [OpalBase.Transaction.Output.Unspent] {
            let walletInputs = await addressBook.listUTXOs()
            var matches: [OpalBase.Transaction.Output.Unspent] = []
            for selected in selectedInputs {
                let outpointMatches = walletInputs.filter {
                    $0.previousTransactionHash.naturalOrder
                            == selected.transactionHash
                        && $0.previousTransactionOutputIndex
                            == selected.outputIndex
                }
                guard outpointMatches.count <= 1 else {
                    throw Failure.walletStateMismatch
                }
                guard let input = outpointMatches.first else {
                    guard absenceAllowed else {
                        throw Failure.walletStateMismatch
                    }
                    continue
                }
                guard !requireEveryInputAbsent,
                      input.value == selected.amountSatoshis,
                      input.lockingScript == selected.lockingScript,
                      input.tokenData == nil else {
                    throw Failure.walletStateMismatch
                }
                matches.append(input)
            }
            return matches
        }

        private func retireRecordedReceivingEntries() async throws {
            for output in recordedParticipantOutputs {
                let lockingScript = Data(output.lockingScriptBytes)
                let entries = await addressBook.listAllEntries().filter {
                    $0.address.lockingScript.data == lockingScript
                }
                guard entries.count == 1, let entry = entries.first else {
                    throw Failure.walletStateMismatch
                }
                do {
                    _ = try await addressBook.releaseReservation(
                        address: entry.address,
                        shouldKeepUsed: true
                    )
                } catch {
                    throw Failure.walletCleanupIncomplete
                }
            }
        }

        private func requireRecordedReceivingEntriesRetired() async throws {
            for output in recordedParticipantOutputs {
                let lockingScript = Data(output.lockingScriptBytes)
                let entries = await addressBook.listAllEntries().filter {
                    $0.address.lockingScript.data == lockingScript
                }
                guard entries.count == 1,
                      entries.first?.isReserved == false else {
                    throw Failure.walletCleanupIncomplete
                }
            }
        }

        private func makeBroadcastOutcome() throws -> Outcome {
            guard let reservationRequest = recordedReservationRequest else {
                throw Failure.invalidRecoveryState
            }
            let recordedReference = binding.walletReservationReference

            let reference: OpalFusion.Host.MosaicReservationReference
            let transaction: OpalFusion.Host.MosaicCompleteTransaction
            let approvalPersisted: Bool
            let intentPersisted: Bool
            switch plan {
            case let .broadcastApprovalRequired(
                valueReference,
                valueTransaction,
                valueIntentPersisted
            ):
                reference = valueReference
                transaction = valueTransaction
                approvalPersisted = false
                intentPersisted = valueIntentPersisted
            case let .resumeApprovedBroadcast(
                valueReference,
                valueTransaction,
                valueIntentPersisted
            ):
                reference = valueReference
                transaction = valueTransaction
                approvalPersisted = true
                intentPersisted = valueIntentPersisted
            default:
                throw Failure.invalidRecoveryState
            }
            guard reference == recordedReference else {
                throw Failure.invalidRecoveryState
            }
            let candidate = try MosaicCommittedBroadcastCandidate(
                authorizedBy: self,
                reservationRequest: reservationRequest,
                reservationReference: reference,
                completeTransaction: transaction,
                journal: journal,
                approvalPersisted: approvalPersisted,
                broadcastIntentPersisted: intentPersisted
            )
            return approvalPersisted
                ? .resumeApprovedBroadcast(candidate)
                : .broadcastApprovalRequired(candidate)
        }

        private var recordedSelectedInputs:
            [MosaicAttemptJournal.SelectedInput]? {
            records.compactMap { record in
                switch record {
                case let .reservationIntent(_, _, inputs, _),
                     let .reservationPrepared(_, inputs, _, _):
                    return inputs
                default:
                    return nil
                }
            }.first
        }

        private var recordedReservationLease:
            OpalFusion.Host.MosaicReservationLease? {
            records.compactMap { record in
                switch record {
                case let .reservationPrepared(_, _, _, lease),
                     let .reserved(lease):
                    return lease
                default:
                    return nil
                }
            }.first
        }

        private var recordedReservationRequest:
            OpalFusion.Host.MosaicReservationRequest? {
            records.compactMap { record in
                switch record {
                case let .reservationIntent(_, request, _, _),
                     let .reservationPrepared(request, _, _, _):
                    return request
                default:
                    return nil
                }
            }.first
        }

        private var recordedSigningRequest:
            OpalFusion.Host.MosaicTransactionSigningRequest? {
            records.compactMap { record
                -> OpalFusion.Host.MosaicTransactionSigningRequest? in
                guard case let .signingIntent(request) = record else {
                    return nil
                }
                return request
            }.last
        }

        private var recordedLocallySignedTransaction:
            OpalFusion.Host.FinalizedTransaction? {
            records.compactMap { record
                -> OpalFusion.Host.FinalizedTransaction? in
                guard case let .locallySigned(_, transaction) = record else {
                    return nil
                }
                return transaction
            }.last
        }

        private var recordedCompleteTransaction:
            OpalFusion.Host.MosaicCompleteTransaction? {
            records.compactMap { record
                -> OpalFusion.Host.MosaicCompleteTransaction? in
                guard case let .commitIntent(_, transaction) = record else {
                    return nil
                }
                return transaction
            }.first
        }

        private var planHasCommittedWalletDisposition: Bool {
            switch plan {
            case .broadcastApprovalRequired, .broadcastReconciliationHeld,
                 .resumeApprovedBroadcast, .reconcileChain:
                return true
            case let .terminal(disposition):
                guard case .chainFinalized = disposition else { return false }
                return true
            default:
                return false
            }
        }

        private func makeBroadcastContext(
            using transactionClient: MosaicNetworkAttestedTransactionClient
        ) async throws -> BroadcastContext {
            guard let reservationRequest = recordedReservationRequest,
                  let profile = recordedProfile,
                  transactionClient.network.supportsMosaicProfile(profile),
                  reservationRequest.networkGenesisHash
                    == transactionClient.network.mosaicGenesisHash else {
                throw Failure.invalidNetworkBinding
            }

            let reference: OpalFusion.Host.MosaicReservationReference
            let completeTransaction: OpalFusion.Host
                .MosaicCompleteTransaction
            let approvalPersisted: Bool
            let intentPersisted: Bool
            switch plan {
            case let .broadcastApprovalRequired(
                valueReference,
                valueTransaction,
                valueIntentPersisted
            ):
                reference = valueReference
                completeTransaction = valueTransaction
                approvalPersisted = false
                intentPersisted = valueIntentPersisted
            case let .resumeApprovedBroadcast(
                valueReference,
                valueTransaction,
                valueIntentPersisted
            ):
                reference = valueReference
                completeTransaction = valueTransaction
                approvalPersisted = true
                intentPersisted = valueIntentPersisted
            case .broadcastReconciliationHeld:
                throw Failure.broadcastReconciliationRequired
            default:
                throw Failure.invalidRecoveryState
            }

            try await requireCommittedWalletState()
            let exactTransaction = try MosaicExactTransaction(
                completeTransaction
            )
            let approvalValues = try broadcastApprovalValues(
                exactTransaction: exactTransaction
            )
            return BroadcastContext(
                reference: reference,
                completeTransaction: completeTransaction,
                exactTransaction: exactTransaction,
                approvalPersisted: approvalPersisted,
                intentPersisted: intentPersisted,
                approvalRequest: .init(
                    reservationRequest: reservationRequest,
                    reservationReference: reference,
                    completeTransaction: completeTransaction,
                    profile: profile,
                    network: transactionClient.network,
                    totalInputSatoshis: approvalValues.totalInputSatoshis,
                    totalOutputSatoshis: approvalValues.totalOutputSatoshis,
                    feeSatoshis: approvalValues.feeSatoshis
                )
            )
        }

        private func broadcastApprovalValues(
            exactTransaction: MosaicExactTransaction
        ) throws -> (
            totalInputSatoshis: UInt64,
            totalOutputSatoshis: UInt64,
            feeSatoshis: UInt64
        ) {
            guard let signingRequest = recordedSigningRequest else {
                throw Failure.invalidRecoveryState
            }
            _ = try MosaicCompleteTransactionValidator.validateComplete(
                exactTransaction.completeTransaction,
                signingRequest: signingRequest
            )
            guard let totalInputSatoshis = Self.sumSatoshis(
                signingRequest.spentInputs.map(\.amountSatoshis)
            ),
                  let totalOutputSatoshis = Self.sumSatoshis(
                    exactTransaction.transaction.outputs.map(\.value)
                  ),
                  totalInputSatoshis >= totalOutputSatoshis else {
                throw Failure.invalidRecoveryState
            }
            return (
                totalInputSatoshis,
                totalOutputSatoshis,
                totalInputSatoshis - totalOutputSatoshis
            )
        }

        private static func sumSatoshis(
            _ values: [UInt64]
        ) -> UInt64? {
            var total: UInt64 = 0
            for value in values {
                let addition = total.addingReportingOverflow(value)
                guard !addition.overflow else { return nil }
                total = addition.partialValue
            }
            return total
        }

        private var recordedProfile: OpalFusion.Mosaic.Profile? {
            guard let request = recordedReservationRequest else { return nil }
            let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
            guard profile.networkGenesisHash == request.networkGenesisHash,
                  profile.transactionProfileIdentifier
                    == request.transactionProfileIdentifier else {
                return nil
            }
            return profile
        }

        private var recordedParticipantOutputs:
            [OpalFusion.Host.ParticipantOutput] {
            records.compactMap { record in
                switch record {
                case let .reservationPrepared(_, _, _, lease),
                     let .reserved(lease):
                    return lease.participantReservation.outputs
                default:
                    return nil
                }
            }.first ?? []
        }

        private func beginOperation() throws {
            guard lifecycle == .ready else {
                throw Failure.operationInProgress
            }
            lifecycle = .performing
        }

        private func requireReplayReadAvailable() throws {
            switch lifecycle {
            case .ready:
                return
            case .terminal:
                return
            case .erasureAuthorizing, .erasureAuthorized:
                throw MosaicHostFailure.terminalReservation
            case .performing:
                throw MosaicHostFailure.reconciliationRequired
            }
        }

        private func requireReplayMutationAvailable() throws {
            guard lifecycle == .ready else {
                throw MosaicHostFailure.terminalReservation
            }
        }

        private func requireMatchingReplayReference(
            _ reference: OpalFusion.Host.MosaicReservationReference
        ) throws {
            guard reference == binding.walletReservationReference else {
                throw MosaicHostFailure.staleReservationReference
            }
        }

        private func finishOperation(with outcome: Outcome) {
            issuedOutcome = outcome
            if case .terminal = outcome {
                lifecycle = .terminal
            } else {
                lifecycle = .ready
            }
        }

        private func resetOperationAfterFailure() {
            if lifecycle == .performing {
                lifecycle = .ready
            }
        }
    }
}
#endif
