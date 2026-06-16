// SpendPlanBroadcastValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Spend plan broadcast", .tags(.unit, .wallet, .transaction, .cashTokens))
struct SpendPlanBroadcastValidator {
    @Test("buildTransaction reports actual change when recipient matches reserved change")
    func spendPlanBuildTransactionReportsActualChangeWhenRecipientMatchesReservedChange() async throws {
        let account = try await SpendPlanBroadcastAccountFixture.makeAccountWithoutOutputRandomization()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 45_000,
            hashByte: 0x70
        )
        let changeEntries = await account.addressBook.listEntries(for: .change)
        let firstChange = try #require(changeEntries.first { $0.derivationPath.index == 0 })
        let paymentAmount = try OpalBase.Satoshi(15_000)
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(address: firstChange.address, amount: paymentAmount)
            ]
        )
        let plan = try await account.prepareSpend(payment)

        let result = try plan.buildTransaction()
        let expectedChange = selectedInput.value - paymentAmount.uint64 - result.fee.uint64

        #expect(expectedChange > paymentAmount.uint64)
        let change = try #require(result.change)
        #expect(change.derivedAddress.address == firstChange.address)
        #expect(change.amount.uint64 == expectedChange)
    }

    @Test("buildAndBroadcast completes spend reservations on success")
    func spendPlanBuildAndBroadcastCompletesReservation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 45_000,
            hashByte: 0x71
        )
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
                    amount: try OpalBase.Satoshi(15_000)
                )
            ]
        )
        let plan = try await account.prepareSpend(payment)

        let handler = TransactionHandlingTestActor(
            deriveBroadcastTransactionHash: true
        )
        let result = try await plan.buildAndBroadcast(via: handler)

        let broadcasts = await handler.readBroadcastedTransactions()
        #expect(broadcasts.count == 1)
        let expectedHash = try BroadcastHashExpectation.makeHash(from: broadcasts)
        #expect(result.hash == expectedHash)

        let changeEntries = await account.addressBook.listEntries(for: .change)
        let firstChange = try #require(changeEntries.first { $0.derivationPath.index == 0 })
        #expect(firstChange.isUsed == true)
        #expect(firstChange.isReserved == false)
        #expect(await account.addressBook.listUTXOs().contains(selectedInput) == false)
        #expect(await account.addressBook.listSpendableUTXOs().contains(selectedInput) == false)
    }

    @Test("buildAndBroadcast maps spend broadcast failures and keeps reservation active")
    func spendPlanBuildAndBroadcastMapsFailures() async throws {
        let (account, plan) = try await makeSpendPlanForBroadcastValidation(hashByte: 0x73)
        let handler = TransactionHandlingTestActor(
            broadcastResult: .failure(NetworkStubError.forced("spend-failure"))
        )

        let error = try await captureSpendBroadcastAccountError {
            _ = try await plan.buildAndBroadcast(via: handler)
        }
        guard case .broadcastFailed = error else {
            throw SpendBroadcastAccountErrorCaptureFailure.unexpected(error)
        }

        let changeEntries = await account.addressBook.listEntries(for: .change)
        let firstChange = try #require(changeEntries.first { $0.derivationPath.index == 0 })
        #expect(firstChange.isReserved == true)

        try await plan.cancelReservation()
        let afterCancelEntries = await account.addressBook.listEntries(for: .change)
        let released = try #require(afterCancelEntries.first { $0.derivationPath.index == 0 })
        #expect(released.isReserved == false)
    }

    @Test("buildAndBroadcast propagates cancellation without wrapping broadcast failures")
    func spendPlanBuildAndBroadcastPropagatesCancellation() async throws {
        let (_, plan) = try await makeSpendPlanForBroadcastValidation(hashByte: 0x7a)
        let handler = TransactionHandlingTestActor(
            broadcastResult: .failure(CancellationError())
        )

        await #expect(throws: CancellationError.self) {
            _ = try await plan.buildAndBroadcast(via: handler)
        }

        try await plan.cancelReservation()
    }

    private func makeSpendPlanForBroadcastValidation(
        hashByte: UInt8
    ) async throws -> (account: OpalBase.Account, plan: OpalBase.Account.SpendPlan) {
        let account = try await AccountTestFixtures.makeAccount()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 35_000,
            hashByte: hashByte
        )
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
                    amount: try OpalBase.Satoshi(12_000)
                )
            ]
        )
        let plan = try await account.prepareSpend(payment)
        return (account, plan)
    }

    @Test("token spend buildAndBroadcast supports success and failure mapping")
    func tokenSpendPlanBuildAndBroadcastSupportsSuccessAndFailure() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x74, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 100, nft: nil)
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 20_000,
            tokenData: tokenData,
            hashByte: 0x75
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 90_000,
            hashByte: 0x76
        )
        let transfer = OpalBase.Account.TokenTransfer(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.tokenAwareAddressString),
                    amount: try OpalBase.Satoshi(1_000),
                    tokenData: .init(category: category, amount: 40, nft: nil)
                )
            ]
        )

        let successPlan = try await account.prepareTokenSpend(transfer)
        let successHandler = TransactionHandlingTestActor(
            deriveBroadcastTransactionHash: true
        )
        let successResult = try await successPlan.buildAndBroadcast(via: successHandler)
        let broadcasts = await successHandler.readBroadcastedTransactions()
        let expectedHash = try BroadcastHashExpectation.makeHash(from: broadcasts)
        #expect(successResult.hash == expectedHash)

        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 20_000,
            tokenData: tokenData,
            hashByte: 0x77
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 90_000,
            hashByte: 0x79
        )
        let failingPlan = try await account.prepareTokenSpend(transfer)
        let failingHandler = TransactionHandlingTestActor(
            broadcastResult: .failure(NetworkStubError.forced("token-spend-failure"))
        )
        let error = try await captureSpendBroadcastAccountError {
            _ = try await failingPlan.buildAndBroadcast(via: failingHandler)
        }
        guard case .broadcastFailed = error else {
            throw SpendBroadcastAccountErrorCaptureFailure.unexpected(error)
        }
        try await failingPlan.cancelReservation()
    }

    enum SpendBroadcastAccountErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    private func captureSpendBroadcastAccountError(
        _ work: () async throws -> Void
    ) async throws -> OpalBase.Account.Error {
        do {
            try await work()
            throw SpendBroadcastAccountErrorCaptureFailure.didNotThrow
        } catch let error as OpalBase.Account.Error {
            return error
        } catch let error as SpendBroadcastAccountErrorCaptureFailure {
            throw error
        } catch {
            throw SpendBroadcastAccountErrorCaptureFailure.unexpected(error)
        }
    }
}
