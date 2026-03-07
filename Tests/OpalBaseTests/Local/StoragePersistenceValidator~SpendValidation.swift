// StoragePersistenceValidator~SpendValidation.swift

import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("prepareSpend throws when payment has no recipients")
    func rejectPaymentWithoutRecipients() async throws {
        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = OpalBase.Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let payment = OpalBase.Account.Payment(recipients: .init())

        await #expect(throws: OpalBase.Account.Error.paymentHasNoRecipients) {
            _ = try await account.prepareSpend(payment)
        }
    }

    @Test("prepareSpend fails for empty wallets (insufficient funds)")
    func rejectPrepareSpendForEmptyWallet() async throws {
        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: ""
        )
        let wallet = OpalBase.Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let recipientAddress = try await account.reserveNextReceivingAddress()
        let recipientAmount = try OpalBase.Satoshi(1_000)

        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(address: recipientAddress, amount: recipientAmount)
            ]
        )

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected insufficient-funds failure, but prepareSpend succeeded for an empty wallet.")
        } catch let error as OpalBase.Account.Error {
            guard case .coinSelectionFailed(let underlying) = error else {
                Issue.record("Expected coinSelectionFailed, got: \(error)")
                return
            }

            if let txError = underlying as? OpalBase.Transaction.Error {
                switch txError {
                case .insufficientFunds:
                    #expect(true)
                default:
                    Issue.record("Expected OpalBase.Transaction.Error.insufficientFunds, got: \(txError)")
                }
                return
            }

            if let bookError = underlying as? OpalBase.Address.Book.Error, bookError == .insufficientFunds {
                #expect(true)
                return
            }

            Issue.record("coinSelectionFailed with unexpected underlying error: \(underlying)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

