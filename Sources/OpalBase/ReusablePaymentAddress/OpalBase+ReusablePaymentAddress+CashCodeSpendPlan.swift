// OpalBase+ReusablePaymentAddress+CashCodeSpendPlan.swift

import Foundation
import OpalCrypto

extension _OpalBase.ReusablePaymentAddress {
    /// Reserved account spend prepared for Cash Code v1 prefix grinding.
    public struct CashCodeSpendPlan: Sendable {
        /// Errors produced by the plan's single-use build and reservation lifecycle.
        public enum LifecycleError: Swift.Error, Sendable, Equatable {
            case operationInProgress
            case planAlreadyUsed
            case transactionNotBuilt
            /// The reservation disposition may have been applied before its backend failed.
            case reservationDispositionFailed
        }

        /// The default and hard maximum for production random-nonce grinding.
        public static let defaultMaximumGrindingAttempts = 1_000_000

        public let request: CashCodePaymentRequest
        public let address: OpalBase.ReusablePaymentAddress
        public let payment: Payment
        public let inputs: [OpalBase.Transaction.Output.Unspent]
        public let qualifyingInputIndex: Int
        public let senderOutpoint: OpalBase.Transaction.Outpoint
        public let feeRate: UInt64

        private let signingKeys: [
            OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey
        ]
        private let qualifyingInput: OpalBase.Transaction.Output.Unspent
        private let qualifyingSigningKey: OpalBase.Key.SigningKey
        private let requestedOutput: OpalBase.Transaction.Output
        private let recipientOutputs: [OpalBase.Transaction.Output]
        private let changeOutput: OpalBase.Transaction.Output
        private let shouldAllowDustDonation: Bool
        private let shouldRandomizeRecipientOrdering: Bool
        private let lifecycle: CashCodeSpendPlanLifecycle

        init(
            request: CashCodePaymentRequest,
            address: OpalBase.ReusablePaymentAddress,
            placeholderLockingScript: Data,
            spendPlan: OpalBase.Account.SpendPlan
        ) throws {
            try self.init(
                request: request,
                address: address,
                placeholderLockingScript: placeholderLockingScript,
                signingKeys: spendPlan.signingKeys,
                recipientOutputs: spendPlan.recipientOutputs,
                changeOutput: spendPlan.changeOutput,
                feeRate: spendPlan.feeRate,
                shouldAllowDustDonation: spendPlan.shouldAllowDustDonation,
                shouldRandomizeRecipientOrdering:
                    spendPlan.shouldRandomizeRecipientOrdering,
                reservationHandle: spendPlan.reservationHandle
            )
        }

        init(
            request: CashCodePaymentRequest,
            address: OpalBase.ReusablePaymentAddress,
            placeholderLockingScript: Data,
            tokenSpendPlan: OpalBase.Account.TokenSpendPlan
        ) throws {
            try self.init(
                request: request,
                address: address,
                placeholderLockingScript: placeholderLockingScript,
                signingKeys: tokenSpendPlan.signingKeys,
                recipientOutputs: tokenSpendPlan.organizedTokenOutputs,
                changeOutput: tokenSpendPlan.bchChangeOutput,
                feeRate: tokenSpendPlan.feeRate,
                shouldAllowDustDonation:
                    tokenSpendPlan.shouldAllowDustDonation,
                shouldRandomizeRecipientOrdering:
                    tokenSpendPlan.shouldRandomizeRecipientOrdering,
                reservationHandle: tokenSpendPlan.reservationHandle
            )
        }

        private init(
            request: CashCodePaymentRequest,
            address: OpalBase.ReusablePaymentAddress,
            placeholderLockingScript: Data,
            signingKeys: [
                OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey
            ],
            recipientOutputs: [OpalBase.Transaction.Output],
            changeOutput: OpalBase.Transaction.Output,
            feeRate: UInt64,
            shouldAllowDustDonation: Bool,
            shouldRandomizeRecipientOrdering: Bool,
            reservationHandle: OpalBase.Account.SpendReservation
        ) throws {
            let builder = OpalBase.Transaction.Builder(
                utxoSigningKeyPairs: signingKeys,
                signatureFormat: .schnorr,
                sequence: UInt32.max,
                unlockers: .init()
            )
            let orderedInputs = builder.orderedUnspentOutputs
            let selection = try Self.selectQualifyingInput(
                from: orderedInputs,
                signingKeys: signingKeys
            )
            let qualifyingSigningKey = selection.signingKey

            let senderOutpoint = OpalBase.Transaction.Outpoint(
                selection.input
            )
            let payment = try address.derivePayment(
                from: qualifyingSigningKey,
                spending: senderOutpoint
            )
            let requestedOutput = OpalBase.Transaction.Output(
                value: request.amount.uint64,
                lockingScript: payment.lockingScript,
                tokenData: request.tokenData
            )
            let retargetedOutputs = try Self.retargetRecipientOutput(
                in: recipientOutputs,
                placeholderLockingScript: placeholderLockingScript,
                request: request,
                requestedOutput: requestedOutput
            )

            self.request = request
            self.address = address
            self.payment = payment
            self.inputs = orderedInputs
            self.qualifyingInputIndex = selection.index
            self.senderOutpoint = senderOutpoint
            self.feeRate = feeRate
            self.signingKeys = signingKeys
            self.qualifyingInput = selection.input
            self.qualifyingSigningKey = qualifyingSigningKey
            self.requestedOutput = requestedOutput
            self.recipientOutputs = retargetedOutputs
            self.changeOutput = changeOutput
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.shouldRandomizeRecipientOrdering =
                shouldRandomizeRecipientOrdering
            self.lifecycle = CashCodeSpendPlanLifecycle(
                reservationHandle: reservationHandle
            )
        }

        /// Builds, fee-corrects, signs, and boundedly grinds the designated
        /// qualifying input using random Schnorr nonces.
        public func buildTransaction(
            maximumGrindingAttempts: Int = defaultMaximumGrindingAttempts
        ) async throws -> OpalBase.Transaction {
            try CashCodePrefixGrindingEngine.validateMaximumAttempts(
                maximumGrindingAttempts
            )
            return try await lifecycle.build {
                let baseTransaction = try buildBaseTransaction()
                return try await grindTransaction(
                    baseTransaction: baseTransaction,
                    maximumGrindingAttempts: maximumGrindingAttempts,
                    makeCandidate: { _ in
                        try makeRandomNonceCandidate(
                            from: baseTransaction
                        )
                    }
                )
            }
        }

        /// Completes the underlying account reservation after an accepted
        /// transaction lifecycle.
        public func completeReservation() async throws {
            try await lifecycle.completeReservation()
        }

        /// Releases the underlying account reservation without broadcasting.
        public func cancelReservation() async throws {
            try await lifecycle.cancelReservation()
        }

        func buildTransaction(
            baseTransaction: OpalBase.Transaction,
            maximumGrindingAttempts: Int,
            makeCandidate: @escaping @Sendable (
                Int
            ) async throws -> OpalBase.Transaction
        ) async throws -> OpalBase.Transaction {
            try CashCodePrefixGrindingEngine.validateMaximumAttempts(
                maximumGrindingAttempts
            )
            return try await lifecycle.build {
                try await grindTransaction(
                    baseTransaction: baseTransaction,
                    maximumGrindingAttempts: maximumGrindingAttempts,
                    makeCandidate: makeCandidate
                )
            }
        }

        private func grindTransaction(
            baseTransaction: OpalBase.Transaction,
            maximumGrindingAttempts: Int,
            makeCandidate: @escaping @Sendable (
                Int
            ) async throws -> OpalBase.Transaction
        ) async throws -> OpalBase.Transaction {
            try validateCandidateMutation(
                baseTransaction,
                from: baseTransaction
            )
            return try await CashCodePrefixGrindingEngine.grind(
                maximumAttempts: maximumGrindingAttempts,
                makeCandidate: makeCandidate,
                validateCandidate: { candidate in
                    try validateCandidateMutation(
                        candidate,
                        from: baseTransaction
                    )
                    return address.filterPrefix.matches(
                        candidate.inputs[qualifyingInputIndex]
                    )
                }
            )
        }

        func buildBaseTransaction() throws -> OpalBase.Transaction {
            try OpalBase.Transaction.build(
                utxoSigningKeyPairs: signingKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                outputOrderingStrategy: shouldRandomizeRecipientOrdering
                    ? .privacyRandomized
                    : .canonicalBIP69,
                signatureFormat: .schnorr,
                feePerByte: feeRate,
                shouldAllowDustDonation: shouldAllowDustDonation
            )
        }

        private func makeRandomNonceCandidate(
            from baseTransaction: OpalBase.Transaction
        ) throws -> OpalBase.Transaction {
            let spentOutputs = inputs.map {
                OpalBase.Transaction.Output(
                    value: $0.value,
                    lockingScript: $0.lockingScript,
                    tokenData: $0.tokenData
                )
            }
            return try baseTransaction.signInputInPlace(
                at: qualifyingInputIndex,
                spending: qualifyingInput,
                signingKey: qualifyingSigningKey,
                signatureFormat: .schnorr,
                unlocker: .p2pkh_CheckSig(),
                using: baseTransaction,
                spentOutputs: spentOutputs,
                schnorrNoncePolicy: .random
            )
        }

        private func validateCandidateMutation(
            _ candidate: OpalBase.Transaction,
            from baseTransaction: OpalBase.Transaction
        ) throws {
            guard candidate.version == baseTransaction.version,
                  candidate.lockTime == baseTransaction.lockTime,
                  candidate.outputs == baseTransaction.outputs,
                  candidate.inputs.count == baseTransaction.inputs.count,
                  candidate.inputs.indices.contains(qualifyingInputIndex),
                  try candidate.encode().count
                    == baseTransaction.encode().count,
                  candidate.outputs.contains(requestedOutput)
            else {
                throw Error.invalidPrefixGrindingCandidate
            }

            for index in candidate.inputs.indices {
                let candidateInput = candidate.inputs[index]
                let baseInput = baseTransaction.inputs[index]
                guard candidateInput.previousTransactionHash
                    == baseInput.previousTransactionHash,
                    candidateInput.previousTransactionOutputIndex
                        == baseInput.previousTransactionOutputIndex,
                    candidateInput.sequence == baseInput.sequence,
                    index == qualifyingInputIndex
                        || candidateInput.unlockingScript
                            == baseInput.unlockingScript
                else {
                    throw Error.invalidPrefixGrindingCandidate
                }
            }

            let qualifying = CashCodeQualifyingInput.collect(
                from: candidate
            ).first { $0.index == qualifyingInputIndex }
            guard let qualifying,
                  qualifying.index < CashCodeQualifyingInput.maximumInputCount,
                  qualifying.publicKey == qualifyingSigningKey.publicKey,
                  OpalBase.Transaction.Outpoint(qualifying.input)
                    == senderOutpoint
            else {
                throw Error.invalidPrefixGrindingCandidate
            }
        }

        private static func retargetRecipientOutput(
            in outputs: [OpalBase.Transaction.Output],
            placeholderLockingScript: Data,
            request: CashCodePaymentRequest,
            requestedOutput: OpalBase.Transaction.Output
        ) throws -> [OpalBase.Transaction.Output] {
            var didRetarget = false
            let result = outputs.map { output in
                guard !didRetarget,
                      output.value == request.amount.uint64,
                      output.tokenData == request.tokenData,
                      output.lockingScript == placeholderLockingScript
                else {
                    return output
                }
                didRetarget = true
                return requestedOutput
            }
            guard didRetarget else {
                throw Error.invalidPrefixGrindingCandidate
            }
            return result
        }

        static func selectQualifyingInput(
            from orderedInputs: [OpalBase.Transaction.Output.Unspent],
            signingKeys: [
                OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey
            ]
        ) throws -> (
            index: Int,
            input: OpalBase.Transaction.Output.Unspent,
            signingKey: OpalBase.Key.SigningKey
        ) {
            for (index, input) in orderedInputs
                .prefix(CashCodeQualifyingInput.maximumInputCount)
                .enumerated()
            {
                guard let signingKey = signingKeys[input],
                      input.lockingScript
                        == CashCodeDerivation.makeLockingScript(
                            for: signingKey.publicKey
                        )
                else {
                    continue
                }
                return (index, input, signingKey)
            }
            throw Error.noQualifyingSenderInput
        }
    }
}

actor CashCodeSpendPlanLifecycle {
    typealias ReservationDisposition = @Sendable () async throws -> Void
    typealias LifecycleError = OpalBase.ReusablePaymentAddress
        .CashCodeSpendPlan.LifecycleError

    private enum State {
        case ready
        case building
        case built
        case disposing
        case terminal
    }

    private let completeReservationOperation: ReservationDisposition
    private let cancelReservationOperation: ReservationDisposition
    private var state = State.ready

    init(reservationHandle: OpalBase.Account.SpendReservation) {
        self.init(
            completeReservation: {
                try await reservationHandle.complete()
            },
            cancelReservation: {
                try await reservationHandle.cancel()
            }
        )
    }

    init(
        completeReservation: @escaping ReservationDisposition,
        cancelReservation: @escaping ReservationDisposition
    ) {
        self.completeReservationOperation = completeReservation
        self.cancelReservationOperation = cancelReservation
    }

    func build(
        _ operation: @Sendable () async throws -> OpalBase.Transaction
    ) async throws -> OpalBase.Transaction {
        switch state {
        case .ready:
            state = .building
        case .building, .disposing:
            throw LifecycleError.operationInProgress
        case .built, .terminal:
            throw LifecycleError.planAlreadyUsed
        }

        do {
            try Task.checkCancellation()
            let transaction = try await operation()
            try Task.checkCancellation()
            state = .built
            return transaction
        } catch {
            let buildError = error
            try await dispose(using: cancelReservationOperation)
            throw buildError
        }
    }

    func completeReservation() async throws {
        switch state {
        case .built:
            break
        case .ready:
            throw LifecycleError.transactionNotBuilt
        case .building, .disposing:
            throw LifecycleError.operationInProgress
        case .terminal:
            throw LifecycleError.planAlreadyUsed
        }

        try await dispose(using: completeReservationOperation)
    }

    func cancelReservation() async throws {
        switch state {
        case .ready, .built:
            break
        case .building, .disposing:
            throw LifecycleError.operationInProgress
        case .terminal:
            throw LifecycleError.planAlreadyUsed
        }

        try await dispose(using: cancelReservationOperation)
    }

    private func dispose(
        using operation: @escaping ReservationDisposition
    ) async throws {
        state = .disposing
        do {
            try await Task {
                try await operation()
            }.value
            state = .terminal
        } catch {
            state = .terminal
            throw LifecycleError.reservationDispositionFailed
        }
    }
}
