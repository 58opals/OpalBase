// CashCodeSenderValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Cash Code sender", .tags(.unit, .wallet, .transaction))
struct CashCodeSenderValidator {
    @Test("sender prepares a BCH payment and accepts only a matching final prefix")
    func prepareAndGrindBitcoinCashPayment() async throws {
        let plan = try await prepareBitcoinCashPlan(hashByte: 0x71)
        let baseTransaction = try plan.buildBaseTransaction()
        let prefixMiss = try makeCandidate(
            from: baseTransaction,
            plan: plan,
            shouldMatch: false
        )
        let prefixMatch = try makeCandidate(
            from: baseTransaction,
            plan: plan,
            shouldMatch: true
        )
        let candidateActor = CashCodePrefixCandidateActor(
            candidates: [prefixMiss, prefixMiss, prefixMatch]
        )

        let transaction = try await plan.buildTransaction(
            baseTransaction: baseTransaction,
            maximumGrindingAttempts: 3,
            makeCandidate: { attempt in
                try await candidateActor.makeCandidate(at: attempt)
            }
        )

        #expect(await candidateActor.readRequestCount() == 3)
        #expect(
            plan.address.filterPrefix.matches(
                transaction.inputs[plan.qualifyingInputIndex]
            )
        )
        #expect(plan.qualifyingInputIndex < 30)
        #expect(
            OpalBase.Transaction.Outpoint(
                transaction.inputs[plan.qualifyingInputIndex]
            ) == plan.senderOutpoint
        )
        #expect(
            transaction.outputs.contains {
                $0.value == plan.request.amount.uint64
                    && $0.tokenData == nil
                    && $0.lockingScript == plan.payment.lockingScript
            }
        )
        let qualifying = CashCodeQualifyingInput.collect(from: transaction)
        #expect(
            qualifying.contains {
                $0.index == plan.qualifyingInputIndex
            }
        )
        try await plan.cancelReservation()
    }

    @Test("sender preserves the complete requested CashToken payload")
    func prepareAndGrindCashTokenPayment() async throws {
        let account = try await SpendPlanBroadcastAccountFixture
            .makeAccountWithoutOutputRandomization()
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0xA7, count: 32)
        )
        let tokenData = OpalBase.CashTokens.TokenData(
            category: category,
            amount: 5,
            nft: try .init(
                capability: .mutable,
                commitment: Data([0x01, 0x02, 0x03])
            )
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 2_000,
            tokenData: tokenData,
            hashByte: 0x72
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 200_000,
            hashByte: 0x73
        )
        let request = OpalBase.ReusablePaymentAddress
            .CashCodePaymentRequest(
                amount: try OpalBase.Satoshi(1_000),
                tokenData: tokenData
            )
        let plan = try await OpalBase.WalletTransactionAuthoringInteractor(
            privateAccount: account
        ).prepareCashCodePayment(
            request,
            to: ReusablePaymentAddressFixtureData.makeAddress(),
            expectedNetwork: .mainnet
        )
        let baseTransaction = try plan.buildBaseTransaction()
        let prefixMatch = try makeCandidate(
            from: baseTransaction,
            plan: plan,
            shouldMatch: true
        )

        let transaction = try await plan.buildTransaction(
            baseTransaction: baseTransaction,
            maximumGrindingAttempts: 1,
            makeCandidate: { _ in prefixMatch }
        )

        let output = try #require(transaction.outputs.first {
            $0.lockingScript == plan.payment.lockingScript
        })
        #expect(output.value == 1_000)
        #expect(output.tokenData == tokenData)
        try await plan.cancelReservation()
    }

    @Test("sender grinding rejects zero work and reports exact exhaustion")
    func enforceGrindingBound() async throws {
        let plan = try await prepareBitcoinCashPlan(hashByte: 0x74)
        let baseTransaction = try plan.buildBaseTransaction()
        let prefixMiss = try makeCandidate(
            from: baseTransaction,
            plan: plan,
            shouldMatch: false
        )
        let candidateActor = CashCodePrefixCandidateActor(
            candidates: [prefixMiss]
        )

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .invalidPrefixGrindingAttemptLimit
        ) {
            _ = try await plan.buildTransaction(
                baseTransaction: baseTransaction,
                maximumGrindingAttempts: 0,
                makeCandidate: { attempt in
                    try await candidateActor.makeCandidate(at: attempt)
                }
            )
        }
        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .invalidPrefixGrindingAttemptLimit
        ) {
            _ = try await plan.buildTransaction(
                baseTransaction: baseTransaction,
                maximumGrindingAttempts: OpalBase.ReusablePaymentAddress
                    .CashCodeSpendPlan.defaultMaximumGrindingAttempts + 1,
                makeCandidate: { attempt in
                    try await candidateActor.makeCandidate(at: attempt)
                }
            )
        }
        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .prefixGrindingExhausted(attempts: 2)
        ) {
            _ = try await plan.buildTransaction(
                baseTransaction: baseTransaction,
                maximumGrindingAttempts: 2,
                makeCandidate: { attempt in
                    try await candidateActor.makeCandidate(at: attempt)
                }
            )
        }
        #expect(await candidateActor.readRequestCount() == 2)
        try await plan.cancelReservation()
    }

    @Test("production random-nonce signing yields a valid hit or exact exhaustion")
    func exerciseProductionRandomNonceSigning() async throws {
        let plan = try await prepareBitcoinCashPlan(hashByte: 0x79)

        do {
            let transaction = try await plan.buildTransaction(
                maximumGrindingAttempts: 1
            )
            #expect(
                plan.address.filterPrefix.matches(
                    transaction.inputs[plan.qualifyingInputIndex]
                )
            )
            #expect(
                transaction.outputs.contains {
                    $0.value == plan.request.amount.uint64
                        && $0.lockingScript == plan.payment.lockingScript
                        && $0.tokenData == plan.request.tokenData
                }
            )
        } catch let error as OpalBase.ReusablePaymentAddress.Error {
            guard error == .prefixGrindingExhausted(attempts: 1) else {
                throw error
            }
        }

        try await plan.cancelReservation()
    }

    @Test("sender grinding cancellation stops before accepting a candidate")
    func cancelPrefixGrinding() async throws {
        let plan = try await prepareBitcoinCashPlan(hashByte: 0x75)
        let baseTransaction = try plan.buildBaseTransaction()
        let prefixMatch = try makeCandidate(
            from: baseTransaction,
            plan: plan,
            shouldMatch: true
        )
        let candidateActor = CashCodePrefixCandidateActor(
            candidates: [prefixMatch]
        )
        await candidateActor.suspendNextRequest()

        let task = Task {
            try await plan.buildTransaction(
                baseTransaction: baseTransaction,
                maximumGrindingAttempts: 1,
                makeCandidate: { attempt in
                    try await candidateActor.makeCandidate(at: attempt)
                }
            )
        }
        await candidateActor.waitForSuspendedRequest()
        task.cancel()
        await candidateActor.resumeRequest()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        try await plan.cancelReservation()
    }

    @Test("sender rejects candidates that mutate non-grinding transaction fields")
    func rejectInvalidGrindingCandidate() async throws {
        let plan = try await prepareBitcoinCashPlan(hashByte: 0x76)
        let baseTransaction = try plan.buildBaseTransaction()
        var outputs = baseTransaction.outputs
        let original = try #require(outputs.first)
        outputs[0] = .init(
            value: original.value + 1,
            lockingScript: original.lockingScript,
            tokenData: original.tokenData
        )
        let invalid = OpalBase.Transaction(
            version: baseTransaction.version,
            inputs: baseTransaction.inputs,
            outputs: outputs,
            lockTime: baseTransaction.lockTime
        )

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .invalidPrefixGrindingCandidate
        ) {
            _ = try await plan.buildTransaction(
                baseTransaction: baseTransaction,
                maximumGrindingAttempts: 1,
                makeCandidate: { _ in invalid }
            )
        }
        try await plan.cancelReservation()
    }

    @Test("sender refuses legacy profiles and explicit network mismatches")
    func rejectLegacyAndWrongNetwork() async throws {
        let account = try await SpendPlanBroadcastAccountFixture
            .makeAccountWithoutOutputRandomization()
        let interactor = OpalBase.WalletTransactionAuthoringInteractor(
            privateAccount: account
        )
        let request = OpalBase.ReusablePaymentAddress
            .CashCodePaymentRequest(
                amount: try OpalBase.Satoshi(10_000)
            )
        let legacy = try OpalBase.ReusablePaymentAddress.Codec().parse(
            ReusablePaymentAddressFixtureData.legacyPaycodeMainnet,
            network: .mainnet
        )

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .legacyProfileIsReadOnly
        ) {
            _ = try await interactor.prepareCashCodePayment(
                request,
                to: legacy,
                expectedNetwork: .mainnet
            )
        }
        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .senderNetworkMismatch
        ) {
            _ = try await interactor.prepareCashCodePayment(
                request,
                to: ReusablePaymentAddressFixtureData.makeAddress(),
                expectedNetwork: .testnet
            )
        }
    }

    @Test("sender never selects a qualifying input beyond position 29")
    func rejectQualifyingInputAfterFirstThirty() throws {
        let signingKey = try ReusablePaymentAddressFixtureData
            .makeSenderSigningKey()
        let validLockingScript = CashCodeDerivation.makeLockingScript(
            for: signingKey.publicKey
        )
        let inputs = (0..<31).map { index in
            OpalBase.Transaction.Output.Unspent(
                value: 1_000,
                lockingScript: index == 30
                    ? validLockingScript
                    : Data([0x51]),
                previousTransactionHash: .init(
                    naturalOrder: Data(
                        repeating: UInt8(index + 1),
                        count: 32
                    )
                ),
                previousTransactionOutputIndex: 0
            )
        }
        let signingKeys = Dictionary(
            uniqueKeysWithValues: inputs.map { ($0, signingKey) }
        )

        #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .noQualifyingSenderInput
        ) {
            _ = try OpalBase.ReusablePaymentAddress.CashCodeSpendPlan
                .selectQualifyingInput(
                    from: inputs,
                    signingKeys: signingKeys
                )
        }
    }

    private func prepareBitcoinCashPlan(
        hashByte: UInt8
    ) async throws -> OpalBase.ReusablePaymentAddress.CashCodeSpendPlan {
        let account = try await SpendPlanBroadcastAccountFixture
            .makeAccountWithoutOutputRandomization()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 200_000,
            hashByte: hashByte
        )
        return try await OpalBase.WalletTransactionAuthoringInteractor(
            privateAccount: account
        ).prepareCashCodePayment(
            .init(amount: try OpalBase.Satoshi(50_000)),
            to: ReusablePaymentAddressFixtureData.makeAddress(),
            expectedNetwork: .mainnet
        )
    }

    private func makeCandidate(
        from transaction: OpalBase.Transaction,
        plan: OpalBase.ReusablePaymentAddress.CashCodeSpendPlan,
        shouldMatch: Bool
    ) throws -> OpalBase.Transaction {
        let input = transaction.inputs[plan.qualifyingInputIndex]
        var unlockingScript = [UInt8](input.unlockingScript)
        guard unlockingScript.count == 100,
              unlockingScript.first == 65,
              unlockingScript[66] == 33
        else {
            throw OpalBase.ReusablePaymentAddress.Error
                .invalidPrefixGrindingCandidate
        }

        for counter in UInt32.min...1_000_000 {
            let bytes = counter.littleEndianData
            unlockingScript.replaceSubrange(1..<5, with: bytes)
            let candidateInput = OpalBase.Transaction.Input(
                previousTransactionHash: input.previousTransactionHash,
                previousTransactionOutputIndex:
                    input.previousTransactionOutputIndex,
                unlockingScript: Data(unlockingScript),
                sequence: input.sequence
            )
            if plan.address.filterPrefix.matches(candidateInput)
                == shouldMatch {
                return try transaction.injectUnlockingScript(
                    Data(unlockingScript),
                    inputIndex: plan.qualifyingInputIndex
                )
            }
        }
        throw OpalBase.ReusablePaymentAddress.Error
            .prefixGrindingExhausted(attempts: 1_000_001)
    }
}
