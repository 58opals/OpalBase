import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("prepareSpend throws when payment has no recipients")
    func rejectPaymentWithoutRecipients() async throws {
        let mnemonic = try MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = WalletActor(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let payment = AccountActor.PaymentModel(recipients: .init())

        await #expect(throws: AccountActor.Error.paymentHasNoRecipients) {
            _ = try await account.prepareSpend(payment)
        }
    }

    @Test("prepareSpend fails for empty wallets (insufficient funds)")
    func rejectPrepareSpendForEmptyWallet() async throws {
        let mnemonic = try MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = WalletActor(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let recipientAddress = try await account.reserveNextReceivingAddress()
        let recipientAmount = try SatoshiModel(1_000)

        let payment = AccountActor.PaymentModel(
            recipients: [
                .init(address: recipientAddress, amount: recipientAmount)
            ]
        )

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected insufficient-funds failure, but prepareSpend succeeded for an empty wallet.")
        } catch let error as AccountActor.Error {
            guard case .coinSelectionFailed(let underlying) = error else {
                Issue.record("Expected coinSelectionFailed, got: \(error)")
                return
            }

            if let txError = underlying as? TransactionModel.Error {
                switch txError {
                case .insufficientFunds:
                    #expect(true)
                default:
                    Issue.record("Expected TransactionModel.Error.insufficientFunds, got: \(txError)")
                }
                return
            }

            if let bookError = underlying as? AddressModel.BookActor.Error, bookError == .insufficientFunds {
                #expect(true)
                return
            }

            Issue.record("coinSelectionFailed with unexpected underlying error: \(underlying)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
