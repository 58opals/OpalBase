// SpendPlanBroadcastValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Spend plan broadcast", .tags(.unit, .wallet, .transaction, .cashTokens))
struct SpendPlanBroadcastValidator {
    @Test("buildAndBroadcast completes spend reservations on success")
    func spendPlanBuildAndBroadcastCompletesReservation() async throws {
        let account = try await AccountTestFixturesModel.makeAccount()
        _ = try await AccountTestFixturesModel.addUnspentOutput(
            to: account,
            value: 45_000,
            hashByte: 0x71
        )
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixturesModel.standardAddressString),
                    amount: try OpalBase.Satoshi(15_000)
                )
            ]
        )
        let plan = try await account.prepareSpend(payment)

        let expectedHash = AccountTestFixturesModel.makeHash(byte: 0x72)
        let handler = TransactionHandlingTestActor(
            broadcastResult: .success(expectedHash.reverseOrder.hexadecimalString)
        )
        let result = try await plan.buildAndBroadcast(via: handler)
        #expect(result.hash == expectedHash)

        let broadcasts = await handler.readBroadcastedTransactions()
        #expect(broadcasts.count == 1)

        let changeEntries = await account.addressBook.listEntries(for: .change)
        let firstChange = changeEntries.first { $0.derivationPath.index == 0 }
        #expect(firstChange?.isUsed == true)
        #expect(firstChange?.isReserved == false)
    }

    @Test("buildAndBroadcast maps spend broadcast failures and keeps reservation active")
    func spendPlanBuildAndBroadcastMapsFailures() async throws {
        let account = try await AccountTestFixturesModel.makeAccount()
        _ = try await AccountTestFixturesModel.addUnspentOutput(
            to: account,
            value: 35_000,
            hashByte: 0x73
        )
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixturesModel.standardAddressString),
                    amount: try OpalBase.Satoshi(12_000)
                )
            ]
        )
        let plan = try await account.prepareSpend(payment)
        let handler = TransactionHandlingTestActor(
            broadcastResult: .failure(NetworkStubError.forced("spend-failure"))
        )

        do {
            _ = try await plan.buildAndBroadcast(via: handler)
            Issue.record("Expected spend buildAndBroadcast to throw")
        } catch let error as OpalBase.Account.Error {
            guard case .broadcastFailed = error else {
                Issue.record("Expected broadcastFailed but got \(error)")
                return
            }
        }

        let changeEntries = await account.addressBook.listEntries(for: .change)
        let firstChange = changeEntries.first { $0.derivationPath.index == 0 }
        #expect(firstChange?.isReserved == true)

        try await plan.cancelReservation()
        let afterCancelEntries = await account.addressBook.listEntries(for: .change)
        let released = afterCancelEntries.first { $0.derivationPath.index == 0 }
        #expect(released?.isReserved == false)
    }

    @Test("token spend buildAndBroadcast supports success and failure mapping")
    func tokenSpendPlanBuildAndBroadcastSupportsSuccessAndFailure() async throws {
        let account = try await AccountTestFixturesModel.makeAccount()
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x74, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 100, nft: nil)
        _ = try await AccountTestFixturesModel.addUnspentOutput(
            to: account,
            value: 20_000,
            tokenData: tokenData,
            hashByte: 0x75
        )
        _ = try await AccountTestFixturesModel.addUnspentOutput(
            to: account,
            value: 90_000,
            hashByte: 0x76
        )
        let transfer = OpalBase.Account.TokenTransfer(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixturesModel.tokenAwareAddressString),
                    amount: try OpalBase.Satoshi(1_000),
                    tokenData: .init(category: category, amount: 40, nft: nil)
                )
            ]
        )

        let successPlan = try await account.prepareTokenSpend(transfer)
        let expectedHash = AccountTestFixturesModel.makeHash(byte: 0x77)
        let successHandler = TransactionHandlingTestActor(
            broadcastResult: .success(expectedHash.reverseOrder.hexadecimalString)
        )
        let successResult = try await successPlan.buildAndBroadcast(via: successHandler)
        #expect(successResult.hash == expectedHash)

        let failingPlan = try await account.prepareTokenSpend(transfer)
        let failingHandler = TransactionHandlingTestActor(
            broadcastResult: .failure(NetworkStubError.forced("token-spend-failure"))
        )
        do {
            _ = try await failingPlan.buildAndBroadcast(via: failingHandler)
            Issue.record("Expected token spend buildAndBroadcast to throw")
        } catch let error as OpalBase.Account.Error {
            guard case .broadcastFailed = error else {
                Issue.record("Expected broadcastFailed but got \(error)")
                return
            }
        }
        try await failingPlan.cancelReservation()
    }
}

