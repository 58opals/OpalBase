// StoragePersistenceValidator~SpendValidation.swift

import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("prepareSpend throws when payment has no recipients")
    func rejectPaymentWithoutRecipients() async throws {
        let wallet = try await AccountTestFixtures.makeWallet()

        let account = try await wallet.fetchAccount(at: 0)
        let payment = OpalBase.Account.Payment(recipients: .init())

        await #expect(throws: OpalBase.Account.Error.paymentHasNoRecipients) {
            _ = try await account.prepareSpend(payment)
        }
    }

    @Test("prepareSpend fails for empty wallets (insufficient funds)")
    func rejectPrepareSpendForEmptyWallet() async throws {
        let wallet = try await AccountTestFixtures.makeWallet()

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
                guard case .insufficientFunds = txError else {
                    Issue.record("Expected Transaction.Error.insufficientFunds, got: \(txError)")
                    return
                }
                return
            }

            if let bookError = underlying as? OpalBase.Address.Book.Error {
                #expect(bookError == OpalBase.Address.Book.Error.insufficientFunds)
                return
            }

            Issue.record("coinSelectionFailed with unexpected underlying error: \(underlying)")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
