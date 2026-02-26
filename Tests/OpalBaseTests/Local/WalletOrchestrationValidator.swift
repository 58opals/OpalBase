import Foundation
import Testing
@testable import OpalBase

@Suite("WalletActor orchestration", .tags(.unit, .wallet))
struct WalletOrchestrationValidator {
    @Test("prepareSpend(forAccountAt:) delegates to the selected account")
    func prepareSpendDelegatesToSelectedAccount() async throws {
        let wallet = try await AccountTestFixturesModel.makeWallet(accountIndices: [0])
        let account = try await wallet.fetchAccount(at: 0)
        _ = try await AccountTestFixturesModel.addUnspentOutput(
            to: account,
            value: 25_000,
            hashByte: 0x01
        )

        let recipient = AccountActor.PaymentModel.Recipient(
            address: try AddressModel(AccountTestFixturesModel.standardAddressString),
            amount: try SatoshiModel(10_000)
        )
        let payment = AccountActor.PaymentModel(recipients: [recipient])

        let plan = try await wallet.prepareSpend(forAccountAt: 0, payment: payment)
        #expect(plan.inputs.count == 1)
        try await plan.cancelReservation()
    }

    @Test("prepareSpend(forAccountAt:) surfaces cannotFetchAccount for missing indices")
    func prepareSpendPropagatesMissingAccountErrors() async throws {
        let wallet = WalletActor(mnemonic: try AccountTestFixturesModel.makeMnemonic())
        let payment = AccountActor.PaymentModel(
            recipients: [
                .init(
                    address: try AddressModel(AccountTestFixturesModel.standardAddressString),
                    amount: try SatoshiModel(1_000)
                )
            ]
        )

        await #expect(throws: WalletActor.Error.cannotFetchAccount(index: 9)) {
            _ = try await wallet.prepareSpend(forAccountAt: 9, payment: payment)
        }
    }

    @Test("calculateBalance aggregates across accounts and updates cached totals")
    func calculateBalanceAggregatesAcrossAccounts() async throws {
        let wallet = try await AccountTestFixturesModel.makeWallet(accountIndices: [0, 1])
        let account0 = try await wallet.fetchAccount(at: 0)
        let account1 = try await wallet.fetchAccount(at: 1)

        let account0Address = try await account0.selectNextEntry(for: .receiving).address
        let account1Address = try await account1.selectNextEntry(for: .receiving).address

        let balanceByAddress: [AddressModel: SatoshiModel] = [
            account0Address: try SatoshiModel(1_200),
            account1Address: try SatoshiModel(3_400)
        ]

        let liveTotal = try await wallet.calculateBalance { address in
            balanceByAddress[address] ?? SatoshiModel()
        }
        let expectedTotal = try SatoshiModel(1_200) + SatoshiModel(3_400)
        #expect(liveTotal == expectedTotal)

        let cachedTotal = try await wallet.calculateCachedBalance()
        #expect(cachedTotal == expectedTotal)
    }

    @Test("applySnapshot replaces account state when wallet identity matches")
    func applySnapshotReplacesAccountState() async throws {
        let sourceWallet = try await AccountTestFixturesModel.makeWallet(accountIndices: [0, 3])
        let sourceAccount = try await sourceWallet.fetchAccount(at: 0)
        _ = try await sourceAccount.reserveNextReceivingAddress()
        let snapshot = await sourceWallet.makeSnapshot()

        let targetWallet = WalletActor(mnemonic: try AccountTestFixturesModel.makeMnemonic())
        try await targetWallet.addAccount(unhardenedIndex: 7)

        try await targetWallet.applySnapshot(snapshot)

        _ = try await targetWallet.fetchAccount(at: 0)
        _ = try await targetWallet.fetchAccount(at: 3)

        let restoredAccount = try await targetWallet.fetchAccount(at: 0)
        let nextReceiving = try await restoredAccount.selectNextEntry(for: .receiving)
        #expect(nextReceiving.derivationPath.index == 1)

        await #expect(throws: WalletActor.Error.cannotFetchAccount(index: 7)) {
            _ = try await targetWallet.fetchAccount(at: 7)
        }
    }

    @Test("applySnapshot rejects snapshots from a different wallet identity")
    func applySnapshotRejectsIdentityMismatch() async throws {
        let wallet = try await AccountTestFixturesModel.makeWallet(accountIndices: [0])
        let snapshot = await wallet.makeSnapshot()

        let mismatchedSnapshot = WalletActor.SnapshotModel(
            words: snapshot.words,
            passphrase: "different-passphrase",
            purpose: snapshot.purpose,
            coinType: snapshot.coinType,
            accounts: snapshot.accounts,
            tokenMetadata: snapshot.tokenMetadata
        )

        await #expect(throws: WalletActor.Error.snapshotDoesNotMatchWallet) {
            try await wallet.applySnapshot(mismatchedSnapshot)
        }
    }
}
