import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("prepareSpend throws when payment has no recipients")
    func rejectPaymentWithoutRecipients() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let payment = Account.Payment(recipients: .init())

        await #expect(throws: Account.Error.paymentHasNoRecipients) {
            _ = try await account.prepareSpend(payment)
        }
    }

    @Test("prepareSpend fails for empty wallets (insufficient funds)")
    func rejectPrepareSpendForEmptyWallet() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let recipientAddress = try await account.reserveNextReceivingAddress()
        let recipientAmount = try Satoshi(1_000)

        let payment = Account.Payment(
            recipients: [
                .init(address: recipientAddress, amount: recipientAmount)
            ]
        )

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected insufficient-funds failure, but prepareSpend succeeded for an empty wallet.")
        } catch let error as Account.Error {
            guard case .coinSelectionFailed(let underlying) = error else {
                Issue.record("Expected coinSelectionFailed, got: \(error)")
                return
            }

            if let txError = underlying as? Transaction.Error {
                switch txError {
                case .insufficientFunds:
                    #expect(true)
                default:
                    Issue.record("Expected Transaction.Error.insufficientFunds, got: \(txError)")
                }
                return
            }

            if let bookError = underlying as? Address.Book.Error, bookError == .insufficientFunds {
                #expect(true)
                return
            }

            Issue.record("coinSelectionFailed with unexpected underlying error: \(underlying)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
