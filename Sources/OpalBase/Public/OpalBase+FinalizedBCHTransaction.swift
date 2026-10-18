import Foundation

public extension OpalBase {
    struct BCHSpendReview: Sendable {
        public let network: Network.Environment
        public let envelope: WalletUnsignedTransactionEnvelope
        public let templateDigest: Data
        public let inputs: [Transaction.Output.Unspent]
        public let fee: Satoshi
        public let change: Account.SpendPlan.TransactionResult.Change?
    }

    enum BCHSubmissionError: Swift.Error, Sendable, Equatable {
        case invalidTransaction
        case inactiveReservation
        case transactionAlreadyFinalized
        case reservationAlreadyClaimed
        case invalidAdmission
        case networkMismatch
        case addressAllocationBlocked
        case staleFrontier
    }

    /// Immutable BCH bytes and selected-output evidence. This value carries no signing authority.
    /// Restoring it validates canonical encoding and accounting, not signatures or relay history.
    struct FinalizedBCHTransaction: Sendable {
        public let rawBytes: Data
        public let hash: Transaction.Hash
        public let network: Network.Environment
        public let transaction: Transaction
        public let inputs: [Transaction.Output.Unspent]
        public let fee: Satoshi
        public let change: Account.SpendPlan.TransactionResult.Change?

        public init(rawBytes: Data, network: Network.Environment,
                    inputs: [Transaction.Output.Unspent],
                    change: Account.SpendPlan.TransactionResult.Change? = nil) throws {
            let decoded = try Transaction.decode(from: rawBytes)
            guard decoded.bytesRead == rawBytes.count,
                  try decoded.transaction.encode() == rawBytes,
                  !inputs.isEmpty, inputs.count == decoded.transaction.inputs.count,
                  inputs.allSatisfy({ $0.tokenData == nil }),
                  decoded.transaction.outputs.allSatisfy({ $0.tokenData == nil }),
                  decoded.transaction.inputs.allSatisfy({ !$0.unlockingScript.isEmpty }) else {
                throw BCHSubmissionError.invalidTransaction
            }
            var unmatched = inputs
            for input in decoded.transaction.inputs {
                guard let index = unmatched.firstIndex(where: {
                    $0.previousTransactionHash == input.previousTransactionHash &&
                    $0.previousTransactionOutputIndex == input.previousTransactionOutputIndex
                }) else { throw BCHSubmissionError.invalidTransaction }
                unmatched.remove(at: index)
            }
            guard Set(inputs).count == inputs.count else { throw BCHSubmissionError.invalidTransaction }
            let totalInput = try Satoshi.sum(of: inputs) { try Satoshi($0.value) }
            let totalOutput = try Satoshi.sum(of: decoded.transaction.outputs) { try Satoshi($0.value) }
            guard totalInput >= totalOutput else { throw BCHSubmissionError.invalidTransaction }
            if let change {
                guard decoded.transaction.outputs.contains(where: {
                    $0.lockingScript == change.derivedAddress.address.lockingScript.data &&
                    $0.value == change.amount.uint64
                }) else { throw BCHSubmissionError.invalidTransaction }
            }
            self.rawBytes = Data(rawBytes)
            self.network = network
            self.transaction = decoded.transaction
            self.inputs = inputs
            self.fee = try totalInput - totalOutput
            self.change = change
            self.hash = .init(naturalOrder: OpalCryptoAdapter.hash256(rawBytes))
        }
    }

    struct BCHRelayOutcome: Sendable {
        public let hash: Transaction.Hash
        public let reservationCompletionError: (any Swift.Error)?
    }

    /// Owns one invocation. Cancellation waits for the local invocation to end; it does not
    /// establish that remote transport did not emit or that a transaction was not accepted.
    final class TransactionRelayAttempt: Sendable {
        public let id: UUID
        private let task: Task<BCHRelayOutcome, any Swift.Error>

        public init(id: UUID = UUID(), operation: @escaping @Sendable () async throws -> Transaction.Hash) {
            self.id = id
            self.task = Task {
                BCHRelayOutcome(hash: try await operation(), reservationCompletionError: nil)
            }
        }

        private init(id: UUID, task: Task<BCHRelayOutcome, any Swift.Error>) {
            self.id = id
            self.task = task
        }

        public func value() async throws -> BCHRelayOutcome { try await task.value }

        public func cancelAndWait() async {
            task.cancel()
            _ = await task.result
        }

        func completing(_ completion: @escaping @Sendable () async throws -> Void) -> TransactionRelayAttempt {
            let source = self
            let task = Task<BCHRelayOutcome, any Swift.Error> {
                let outcome = try await withTaskCancellationHandler {
                    try await source.value()
                } onCancel: {
                    source.task.cancel()
                }
                do {
                    try await completion()
                    return outcome
                } catch {
                    return BCHRelayOutcome(hash: outcome.hash, reservationCompletionError: error)
                }
            }
            return .init(id: id, task: task)
        }

        func validating(_ expectedHash: Transaction.Hash) -> TransactionRelayAttempt {
            let source = self
            let task = Task<BCHRelayOutcome, any Swift.Error> {
                let outcome = try await withTaskCancellationHandler {
                    try await source.value()
                } onCancel: { source.task.cancel() }
                guard outcome.hash == expectedHash else { throw BCHSubmissionError.invalidTransaction }
                return outcome
            }
            return .init(id: id, task: task)
        }
    }

    /// A synchronous ownership handoff. `begin` must own exactly one invocation before returning,
    /// must never retry, and must return its actual invocation handle. Emission/reply may be async.
    struct TransactionRelay: Sendable {
        public let network: Network.Environment
        private let performBegin: @Sendable (FinalizedBCHTransaction) -> TransactionRelayAttempt

        public init(network: Network.Environment,
                    begin: @escaping @Sendable (FinalizedBCHTransaction) -> TransactionRelayAttempt) {
            self.network = network
            self.performBegin = begin
        }

        public init(network: Network.Environment, transactionClient: Network.TransactionClient) {
            self.init(network: network) { finalized in
                TransactionRelayAttempt {
                    let identifier = try await transactionClient.broadcastTransaction(
                        rawTransactionHexadecimal: finalized.rawBytes.hexadecimalString)
                    let returned = try Network.decodeTransactionHash(from: identifier)
                    guard returned == finalized.hash else { throw BCHSubmissionError.invalidTransaction }
                    return returned
                }
            }
        }

        public func begin(_ finalized: FinalizedBCHTransaction) throws -> TransactionRelayAttempt {
            guard finalized.network == network else { throw BCHSubmissionError.networkMismatch }
            return performBegin(finalized).validating(finalized.hash)
        }
    }

    /// The middleware must invoke the nonescaping handoff exactly once while holding the
    /// caller's authority/continuity lock. The lock covers final checks, lease claim and handoff.
    typealias BCHSubmissionAdmission = @Sendable (_ claimAndBegin: () throws -> TransactionRelayAttempt) throws -> TransactionRelayAttempt
}

public extension OpalBase.Account.SpendPlan {
    func requireActiveReservation() async throws { try await reservationHandle.requireActive() }

    /// Freezes ordering and fee with fixed-size Schnorr placeholders, without signing.
    func review(network: OpalBase.Network.Environment) async throws -> OpalBase.BCHSpendReview {
        if let review = try await reservationHandle.addressBook.spendReview(for: reservationHandle.reservation) {
            guard review.network == network else { throw OpalBase.BCHSubmissionError.networkMismatch }
            return review
        }
        guard payment.recipients.allSatisfy({ $0.address.network == network }) else {
            throw OpalBase.BCHSubmissionError.networkMismatch
        }
        let envelope = try OpalBase.Transaction.makeUnsignedTransactionEnvelope(
            unspentOutputs: inputs, recipientOutputs: recipientOutputs, changeOutput: changeOutput,
            outputOrderingStrategy: shouldRandomizeRecipientOrdering ? .privacyRandomized : .canonicalBIP69,
            signatureFormat: .schnorr, feePerByte: feeRate, shouldAllowDustDonation: shouldAllowDustDonation)
        let outputs = try OpalBase.Satoshi.sum(of: envelope.unsignedTransaction.outputs) { try .init($0.value) }
        let inputTotal = try OpalBase.Satoshi.sum(of: inputs) { try .init($0.value) }
        let recipientTotal = try OpalBase.Satoshi.sum(of: recipientOutputs) { try .init($0.value) }
        let changeAmount = try outputs - recipientTotal
        let change: TransactionResult.Change? = changeAmount.uint64 == 0 ? nil : .init(entry: reservationHandle.changeEntry, amount: changeAmount)
        let review = OpalBase.BCHSpendReview(network: network, envelope: envelope,
            templateDigest: OpalCryptoAdapter.hash256(try envelope.unsignedTransaction.encode()), inputs: inputs,
            fee: try inputTotal - outputs, change: change)
        return try await reservationHandle.addressBook.retainSpendReview(review, for: reservationHandle.reservation)
    }

    func finalize(network: OpalBase.Network.Environment) async throws -> OpalBase.FinalizedBCHTransaction {
        if let existing = try await reservationHandle.addressBook.finalizedTransaction(for: reservationHandle.reservation) {
            guard existing.network == network else { throw OpalBase.BCHSubmissionError.networkMismatch }
            return existing
        }
        let review = try await review(network: network)
        var transaction = review.envelope.unsignedTransaction
        for (index, input) in transaction.inputs.enumerated() {
            guard let selected = inputs.first(where: {
                $0.previousTransactionHash == input.previousTransactionHash &&
                $0.previousTransactionOutputIndex == input.previousTransactionOutputIndex
            }), let signingKey = signingKeys[selected] else { throw OpalBase.BCHSubmissionError.invalidTransaction }
            transaction = try transaction.signInputInPlace(at: index, spending: selected, signingKey: signingKey,
                signatureFormat: .schnorr, unlocker: .p2pkh_CheckSig(), using: review.envelope.unsignedTransaction)
        }
        try review.envelope.validateSignedTransactionStructure(transaction)
        let finalized = try OpalBase.FinalizedBCHTransaction(rawBytes: transaction.encode(), network: network,
                                                            inputs: inputs, change: review.change)
        guard finalized.fee == review.fee else { throw OpalBase.BCHSubmissionError.invalidTransaction }
        return try await reservationHandle.addressBook.retainFinalizedTransaction(finalized, for: reservationHandle.reservation)
    }

    /// Ends the exact bound local invocation, then disposes this claimed lease after the
    /// caller establishes affirmative, coherent transaction/input/change reconciliation. This
    /// does not establish chain evidence or alter current UTXOs, construct bytes, or relay.
    func completeClaimedReservationAfterReconciliation() async throws {
        try await reservationHandle.addressBook.completeReconciledBCHReservation(reservationHandle.reservation)
    }

    func claimAndHandoff(_ finalized: OpalBase.FinalizedBCHTransaction,
                         using relay: OpalBase.TransactionRelay,
                         admission: OpalBase.BCHSubmissionAdmission) async throws -> OpalBase.TransactionRelayAttempt {
        try await reservationHandle.addressBook.claimAndHandoff(finalized, reservation: reservationHandle.reservation,
                                                               using: relay, admission: admission)
    }
}

extension OpalBase.Address.Book {
    func spendReview(for reservation: SpendReservation) throws -> OpalBase.BCHSpendReview? {
        try validateExactReservation(reservation)
        return bchSpendReviews[reservation.id]
    }

    func retainSpendReview(_ review: OpalBase.BCHSpendReview, for reservation: SpendReservation) throws -> OpalBase.BCHSpendReview {
        try validateExactReservation(reservation)
        if let existing = bchSpendReviews[reservation.id] { return existing }
        bchSpendReviews[reservation.id] = review
        return review
    }

    func validateExactReservation(_ reservation: SpendReservation, allowClaimed: Bool = false) throws {
        try requireSnapshotRefreshAccess()
        guard let state = spendReservationStates[reservation.id], state.reservedAt == reservation.reservationDate,
              utxoStore.containsExact(state.utxos), state.utxos.isSubset(of: utxoStore.reservedUTXOs),
              let entry = findEntry(for: state.entry.address), entry.isReserved,
              entry.derivationPath == state.entry.derivationPath else {
            throw OpalBase.BCHSubmissionError.inactiveReservation
        }
        guard allowClaimed || !claimedBCHReservations.contains(reservation.id) else {
            throw OpalBase.BCHSubmissionError.reservationAlreadyClaimed
        }
        guard allowClaimed || spendReservationExpirationInterval <= 0 ||
              Date().timeIntervalSince(state.reservedAt) < spendReservationExpirationInterval else {
            throw OpalBase.BCHSubmissionError.inactiveReservation
        }
        if !allowClaimed, let revision = boundedBCHFrontierRevisions[reservation.id],
           !isConfirmedFrontierCurrent || confirmedAddressFrontier?.revision != revision {
            throw OpalBase.BCHSubmissionError.staleFrontier
        }
    }

    func finalizedTransaction(for reservation: SpendReservation) throws -> OpalBase.FinalizedBCHTransaction? {
        try validateExactReservation(reservation)
        return finalizedBCHTransactions[reservation.id]
    }

    func retainFinalizedTransaction(_ finalized: OpalBase.FinalizedBCHTransaction,
                                    for reservation: SpendReservation) throws -> OpalBase.FinalizedBCHTransaction {
        try validateExactReservation(reservation)
        if let existing = finalizedBCHTransactions[reservation.id] { return existing }
        finalizedBCHTransactions[reservation.id] = finalized
        return finalized
    }

    func claimAndHandoff(_ finalized: OpalBase.FinalizedBCHTransaction, reservation: SpendReservation,
                         using relay: OpalBase.TransactionRelay,
                         admission: OpalBase.BCHSubmissionAdmission) throws -> OpalBase.TransactionRelayAttempt {
        var actual: OpalBase.TransactionRelayAttempt?
        let returned = try admission {
            try validateExactReservation(reservation)
            guard let retained = finalizedBCHTransactions[reservation.id],
                  retained.rawBytes == finalized.rawBytes, retained.network == finalized.network else {
                throw OpalBase.BCHSubmissionError.invalidTransaction
            }
            claimedBCHReservations.insert(reservation.id)
            cancelAutomaticSpendReservationRelease(for: reservation.id)
            do {
                let invocation = try relay.begin(retained)
                actual = invocation
                return invocation
            } catch {
                claimedBCHReservations.remove(reservation.id)
                scheduleAutomaticSpendReservationRelease(for: reservation.id)
                throw error
            }
        }
        guard let actual, returned === actual else { throw OpalBase.BCHSubmissionError.invalidAdmission }
        let hadChange = finalizedBCHTransactions[reservation.id]?.change != nil
        let completion = actual.completing {
            try await self.completeClaimedBCHReservation(reservation, hadChange: hadChange)
        }
        claimedBCHInvocations[reservation.id] = completion
        return completion
    }

    func completeReconciledBCHReservation(_ reservation: SpendReservation) async throws {
        guard claimedBCHReservations.contains(reservation.id),
              let invocation = claimedBCHInvocations[reservation.id] else { throw OpalBase.BCHSubmissionError.inactiveReservation }
        // This exact claim owns this invocation. End it before changing lease ownership;
        // suspension releases the actor, and all ownership is revalidated afterward.
        await invocation.cancelAndWait()
        if let outcome = try? await invocation.value(), outcome.reservationCompletionError != nil {
            throw OpalBase.BCHSubmissionError.inactiveReservation
        }
        try requireSnapshotRefreshAccess()
        guard claimedBCHReservations.contains(reservation.id),
              let state = spendReservationStates[reservation.id], state.reservedAt == reservation.reservationDate,
              let entry = findEntry(for: state.entry.address), entry.derivationPath == state.entry.derivationPath,
              !spendReservationStates.contains(where: { $0.key != reservation.id && ($0.value.entry.address == state.entry.address || !$0.value.utxos.isDisjoint(with: state.utxos)) }) else {
            throw OpalBase.BCHSubmissionError.inactiveReservation
        }
        // Refresh may already have removed spent inputs or retained unaffected inputs.
        // End ownership only; the synchronized UTXO inventory remains authoritative.
        _ = try releaseReservation(address: state.entry.address, shouldKeepUsed: entry.isUsed || state.hasBeenUsedPreviously)
        utxoStore.release(state.utxos)
        claimedBCHReservations.remove(reservation.id)
        _ = removeReservationState(matching: reservation)
    }

    func completeClaimedBCHReservation(_ reservation: SpendReservation, hadChange: Bool) async throws {
        try validateExactReservation(reservation, allowClaimed: true)
        guard let state = removeReservationState(matching: reservation) else {
            throw OpalBase.BCHSubmissionError.inactiveReservation
        }
        claimedBCHReservations.remove(reservation.id)
        finalizedBCHTransactions.removeValue(forKey: reservation.id)
        utxoStore.remove(Array(state.utxos))
        _ = try releaseReservation(address: state.entry.address, shouldKeepUsed: hadChange || state.hasBeenUsedPreviously)
    }
}
