import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Wallet two-account token spend", .tags(.unit, .wallet, .cashTokens))
struct WalletTokenSpendTwoAccountValidator {
    @Test("token and BCH change remain with their respective input owners")
    func separatesChangeAndSigningOwnership() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        let review = try plan.buildReview()
        let tokenReservation = try #require(await fixture.tokenAccount.addressBook.readActiveSpendReservations().first)
        let payerReservation = try #require(await fixture.payerAccount.addressBook.readActiveSpendReservations().first)

        #expect(plan.tokenInputs == [fixture.tokenInput])
        #expect(plan.bchInputs == [fixture.payerInput])
        #expect(plan.tokenAccountIndex == 1)
        #expect(plan.bchFundingAccountIndex == 0)
        #expect(plan.tokenChangeOutputs.allSatisfy {
            $0.lockingScript == tokenReservation.changeEntry.address.lockingScript.data
        })
        #expect(plan.tokenOwnerBCHChangeOutput?.lockingScript == tokenReservation.changeEntry.address.lockingScript.data)
        #expect(plan.bchChangeOutput.lockingScript == payerReservation.changeEntry.address.lockingScript.data)
        #expect(review.tokenChangeOutputs.count == 1)
        #expect(review.bchChange?.derivedAddress.address == payerReservation.changeEntry.address)
        #expect(review.tokenOwnerBCHChange?.derivedAddress.address == tokenReservation.changeEntry.address)
        #expect(review.transaction.inputs.count == 2)
        let tokenAccountOutputs = plan.tokenChangeOutputs.reduce(0) { $0 + $1.value }
            + (plan.tokenOwnerBCHChangeOutput?.value ?? 0)
        #expect(tokenAccountOutputs == fixture.tokenInput.value)
        let recipientValue = plan.tokenRecipientOutputs.reduce(0) { $0 + $1.value }
        let payerChange = try #require(review.bchChange).amount.uint64
        #expect(fixture.payerInput.value == recipientValue + payerChange + review.fee.uint64)

        try await plan.cancelReservation()
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await fixture.tokenAccount.addressBook.listSpendableUTXOs().contains(fixture.tokenInput))
        #expect(await fixture.payerAccount.addressBook.listSpendableUTXOs().contains(fixture.payerInput))
    }

    @Test("payer reservation failure rolls back the token reservation")
    func payerContentionRollsBackTokenReservation() async throws {
        let fixture = try await makeFixture()
        let payerBook = await fixture.payerAccount.addressBook
        let competingReservation = try await payerBook.selectNextEntry(for: .change)
        var competitor: OpalBase.Address.Book.SpendReservation?
        do {
            _ = try await fixture.tokenAccount.prepareTokenSpend(
                fixture.transfer,
                payingFeesFrom: fixture.payerAccount,
                beforeReservation: { _ in
                    _ = try await payerBook.reserveSpend(
                        utxos: [fixture.payerInput],
                        changeEntry: competingReservation,
                        tokenSelectionPolicy: .excludeTokenUTXOs
                    )
                }
            )
            Issue.record("Expected payer input contention")
        } catch let error as OpalBase.Account.Error {
            guard case .tokenSelectionFailed = error else { throw error }
        }
        competitor = await payerBook.readActiveSpendReservations().first
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await fixture.tokenAccount.addressBook.listSpendableUTXOs().contains(fixture.tokenInput))
        if let competitor {
            try await payerBook.releaseSpendReservation(competitor, outcome: .cancelled)
        }
    }

    @Test("held two-account plan cannot be prepared twice and cancellation permits retry")
    func competingPlanCannotReuseReservations() async throws {
        let fixture = try await makeFixture()
        let first = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        await #expect(throws: OpalBase.Account.Error.self) {
            _ = try await fixture.wallet.prepareTokenSpend(
                forAccountAt: 1,
                payingFeesFromAccountAt: 0,
                transfer: fixture.transfer
            )
        }
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().count == 1)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().count == 1)

        try await first.cancelReservation()
        let retry = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        try await retry.cancelReservation()
    }

    @Test("wallet rejects a BCH payer index outside its accounts")
    func rejectsUnknownPayer() async throws {
        let fixture = try await makeFixture()
        await #expect(throws: OpalBase.Wallet.Error.cannotFetchAccount(index: 7)) {
            _ = try await fixture.wallet.prepareTokenSpend(
                forAccountAt: 1,
                payingFeesFromAccountAt: 7,
                transfer: fixture.transfer
            )
        }
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("token inputs cannot be borrowed from the BCH account")
    func rejectsWrongTokenOwner() async throws {
        let fixture = try await makeFixture()
        await #expect(throws: OpalBase.Account.Error.tokenTransferInsufficientTokens) {
            _ = try await fixture.wallet.prepareTokenSpend(
                forAccountAt: 0,
                payingFeesFromAccountAt: 1,
                transfer: fixture.transfer
            )
        }
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("full token send returns all token-input BCH to the token owner")
    func fullTokenSendPreservesTokenOwnerBCH() async throws {
        let fixture = try await makeFixture()
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x81, count: 32)
        )
        let transfer = OpalBase.Account.TokenTransfer(recipients: [
            .init(
                address: try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString),
                amount: try OpalBase.Satoshi(1_000),
                tokenData: .init(category: category, amount: 100, nft: nil)
            )
        ])
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: transfer
        )
        let review = try plan.buildReview()
        #expect(plan.tokenChangeOutputs.isEmpty)
        #expect(plan.tokenOwnerBCHChangeOutput?.value == fixture.tokenInput.value)
        #expect(review.tokenOwnerBCHChange?.amount.uint64 == fixture.tokenInput.value)
        let payerChange = try #require(review.bchChange).amount.uint64
        #expect(fixture.payerInput.value == 1_000 + payerChange + review.fee.uint64)
        try await plan.cancelReservation()
    }

    @Test("subdust token-input BCH is returned through a funded owner change output")
    func subdustTokenOwnerResidueIsPreserved() async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0, 1])
        let tokenAccount = try await wallet.fetchAccount(at: 1)
        let payerAccount = try await wallet.fetchAccount(at: 0)
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x85, count: 32)
        )
        let tokenInput = try await AccountTestFixtures.addUnspentOutput(
            to: tokenAccount,
            value: 200,
            tokenData: .init(category: category, amount: 100, nft: nil),
            hashByte: 0x86
        )
        let payerInput = try await AccountTestFixtures.addUnspentOutput(
            to: payerAccount,
            value: 100_000,
            hashByte: 0x87
        )
        let transfer = OpalBase.Account.TokenTransfer(recipients: [
            .init(
                address: try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString),
                amount: try OpalBase.Satoshi(1_000),
                tokenData: .init(category: category, amount: 100, nft: nil)
            )
        ])
        let plan = try await wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: transfer
        )
        let review = try plan.buildReview()
        let ownerChange = try #require(review.tokenOwnerBCHChange).amount.uint64
        let payerChange = try #require(review.bchChange).amount.uint64
        #expect(ownerChange > tokenInput.value)
        #expect(payerInput.value + tokenInput.value == 1_000 + ownerChange + payerChange + review.fee.uint64)
        try await plan.cancelReservation()
    }

    @Test("simultaneous plans cannot share either account's inputs")
    func simultaneousPlansReserveAtMostOnce() async throws {
        let fixture = try await makeFixture()
        let plans = await withTaskGroup(of: OpalBase.Account.TokenSpendPlan?.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    try? await fixture.wallet.prepareTokenSpend(
                        forAccountAt: 1,
                        payingFeesFromAccountAt: 0,
                        transfer: fixture.transfer
                    )
                }
            }
            var results: [OpalBase.Account.TokenSpendPlan] = []
            for await plan in group {
                if let plan { results.append(plan) }
            }
            return results
        }
        #expect(plans.count == 1)
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().count == 1)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().count == 1)
        for plan in plans { try await plan.cancelReservation() }
    }

    @Test("same payer and token owner use one reservation")
    func sameAccountKeepsOneReservation() async throws {
        let fixture = try await makeFixture()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: fixture.tokenAccount,
            value: 100_000,
            hashByte: 0x84
        )
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 1,
            transfer: fixture.transfer
        )
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().count == 1)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().isEmpty)
        try await plan.cancelReservation()
    }

    @Test("same-account plans cannot refresh and share one active reservation")
    func simultaneousSameAccountPlansDoNotShareReservation() async throws {
        let fixture = try await makeFixture()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: fixture.tokenAccount,
            value: 100_000,
            hashByte: 0x88
        )
        let gate = TwoPartyPreparationGate()
        let tokenAccount = fixture.tokenAccount
        let transfer = fixture.transfer
        let plans = await withTaskGroup(of: OpalBase.Account.TokenSpendPlan?.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    try? await tokenAccount.prepareTokenSpend(
                        transfer,
                        beforeReservation: { _ in await gate.wait() }
                    )
                }
            }
            var results: [OpalBase.Account.TokenSpendPlan] = []
            for await plan in group {
                if let plan { results.append(plan) }
            }
            return results
        }
        #expect(plans.count == 1)
        #expect(await tokenAccount.addressBook.readActiveSpendReservations().count == 1)
        for plan in plans { try await plan.cancelReservation() }
    }

    @Test("accepted broadcast completes both owners' reservations")
    func acceptedBroadcastCompletesBothReservations() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        let handler = TransactionHandlingTestActor(deriveBroadcastTransactionHash: true)
        let accepted = try await plan.buildAndBroadcast(via: handler)
        let broadcasts = await handler.readBroadcastedTransactions()
        let expectedHash = try BroadcastHashExpectation.makeHash(from: broadcasts)
        #expect(broadcasts.count == 1)
        #expect(accepted.hash == expectedHash)
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await fixture.tokenAccount.addressBook.listUTXOs().contains(fixture.tokenInput) == false)
        #expect(await fixture.payerAccount.addressBook.listUTXOs().contains(fixture.payerInput) == false)
    }

    @Test("rejected broadcast keeps both reservations until explicit cancellation")
    func rejectedBroadcastPreservesReservations() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        let handler = TransactionHandlingTestActor(
            broadcastResult: .failure(NetworkStubError.forced("two-account-rejection"))
        )
        await #expect(throws: OpalBase.Account.Error.self) {
            _ = try await plan.buildAndBroadcast(via: handler)
        }
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().count == 1)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().count == 1)
        try await plan.cancelReservation()
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("expired token reservation prevents relay and payer cancellation still works")
    func expiredReservationPreventsRelay() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        _ = try await fixture.tokenAccount.addressBook.releaseExpiredSpendReservations(olderThan: 0)
        let handler = TransactionHandlingTestActor(deriveBroadcastTransactionHash: true)
        await #expect(throws: OpalBase.Account.Error.self) {
            _ = try await plan.buildAndBroadcast(via: handler)
        }
        #expect(await handler.readBroadcastedTransactions().isEmpty)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().count == 1)
        try await plan.cancelReservation()
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("accepted relay remains visible when local token completion fails")
    func acceptedRelayReportsLocalCompletionFailure() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        let tokenBook = await fixture.tokenAccount.addressBook
        let tokenInput = fixture.tokenInput
        let client = OpalBase.Network.TransactionClient(
            broadcastTransaction: { rawTransaction in
                await tokenBook.removeUTXO(tokenInput)
                let rawData = try Data(hexadecimalString: rawTransaction)
                return OpalBase.Transaction.Hash(
                    naturalOrder: OpalCryptoAdapter.hash256(rawData)
                ).reverseOrder.hexadecimalString
            },
            fetchConfirmations: { _ in nil },
            fetchConfirmationStatus: { hash in
                .init(transactionHash: hash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
            }
        )

        let outcome = try await plan.buildAndBroadcastWithOutcome(via: client)
        #expect(outcome.hash == OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(try outcome.result.transaction.encode())
        ))
        #expect(outcome.reservationCompletionError != nil)
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("reviewed broadcast submits exactly the displayed transaction")
    func reviewedBroadcastPreservesExactBytes() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        let review = try plan.buildReview()
        let handler = TransactionHandlingTestActor(deriveBroadcastTransactionHash: true)
        let outcome = try await plan.broadcastReviewedTransactionWithOutcome(
            review.transaction,
            via: .init(handler)
        )
        let submitted = await handler.readBroadcastedTransactions()
        let expectedHash = try BroadcastHashExpectation.makeHash(from: submitted)
        #expect(submitted == [review.rawTransactionData.hexadecimalString])
        #expect(outcome.reservationCompletionError == nil)
        #expect(outcome.hash == expectedHash)
    }

    @Test("reviewed broadcast refuses substituted outputs before relay")
    func reviewedBroadcastRejectsSubstitutedOutput() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        let review = try plan.buildReview()
        var outputs = review.transaction.outputs
        let tokenOutputIndex = try #require(outputs.firstIndex { $0.tokenData != nil })
        outputs.remove(at: tokenOutputIndex)
        let substituted = OpalBase.Transaction(
            version: review.transaction.version,
            inputs: review.transaction.inputs,
            outputs: outputs,
            lockTime: review.transaction.lockTime
        )
        let handler = TransactionHandlingTestActor(deriveBroadcastTransactionHash: true)
        await #expect(throws: OpalBase.Account.Error.self) {
            _ = try await plan.broadcastReviewedTransactionWithOutcome(
                substituted,
                via: .init(handler)
            )
        }
        #expect(await handler.readBroadcastedTransactions().isEmpty)
        try await plan.cancelReservation()
    }

    @Test("cancelled preflight never submits a reviewed two-account spend")
    func reviewedBroadcastPreflightCancellationSkipsRelay() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        let review = try plan.buildReview()
        let handler = TransactionHandlingTestActor(deriveBroadcastTransactionHash: true)

        let caughtCancellation = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await plan.broadcastReviewedTransactionWithOutcome(
                    review.transaction,
                    via: .init(handler)
                )
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value

        #expect(caughtCancellation)
        #expect(await handler.readBroadcastedTransactions().isEmpty)
        try await plan.cancelReservation()
    }

    @Test("relay cancellation is reported as an uncertain two-account broadcast")
    func reviewedBroadcastWrapsRelayCancellation() async throws {
        let fixture = try await makeFixture()
        let plan = try await fixture.wallet.prepareTokenSpend(
            forAccountAt: 1,
            payingFeesFromAccountAt: 0,
            transfer: fixture.transfer
        )
        let review = try plan.buildReview()
        let handler = TransactionHandlingTestActor(broadcastResult: .failure(CancellationError()))

        var wrappedCancellation = false
        do {
            _ = try await plan.broadcastReviewedTransactionWithOutcome(
                review.transaction,
                via: .init(handler)
            )
        } catch let error as OpalBase.Account.Error {
            if case .broadcastFailed(let underlying) = error {
                wrappedCancellation = underlying is CancellationError
            }
        }

        #expect(wrappedCancellation)
        #expect(await handler.readBroadcastedTransactions().count == 1)
        #expect(await fixture.tokenAccount.addressBook.readActiveSpendReservations().count == 1)
        #expect(await fixture.payerAccount.addressBook.readActiveSpendReservations().count == 1)
        try await plan.cancelReservation()
    }

    private func makeFixture() async throws -> (
        wallet: OpalBase.Wallet,
        tokenAccount: OpalBase.Account,
        payerAccount: OpalBase.Account,
        tokenInput: OpalBase.Transaction.Output.Unspent,
        payerInput: OpalBase.Transaction.Output.Unspent,
        transfer: OpalBase.Account.TokenTransfer
    ) {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0, 1])
        let tokenAccount = try await wallet.fetchAccount(at: 1)
        let payerAccount = try await wallet.fetchAccount(at: 0)
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x81, count: 32))
        let tokenInput = try await AccountTestFixtures.addUnspentOutput(
            to: tokenAccount,
            value: 15_000,
            tokenData: .init(category: category, amount: 100, nft: nil),
            hashByte: 0x82
        )
        let payerInput = try await AccountTestFixtures.addUnspentOutput(
            to: payerAccount,
            value: 100_000,
            hashByte: 0x83
        )
        let transfer = OpalBase.Account.TokenTransfer(recipients: [
            .init(
                address: try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString),
                amount: try OpalBase.Satoshi(1_000),
                tokenData: .init(category: category, amount: 40, nft: nil)
            )
        ])
        return (wallet, tokenAccount, payerAccount, tokenInput, payerInput, transfer)
    }
}

private actor TwoPartyPreparationGate {
    private var arrivals = 0
    private var waiting: CheckedContinuation<Void, Never>?

    func wait() async {
        arrivals += 1
        if arrivals == 2 {
            waiting?.resume()
            waiting = nil
        } else {
            await withCheckedContinuation { continuation in
                waiting = continuation
            }
        }
    }
}
