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

        let error = try await Self.captureSpendValidationAccountError {
            _ = try await account.prepareSpend(payment)
        }

        guard case .coinSelectionFailed(let underlying) = error else {
            throw SpendValidationAccountErrorCaptureFailure.unexpected(error)
        }

        if let txError = underlying as? OpalBase.Transaction.Error {
            guard case .insufficientFunds = txError else {
                throw SpendValidationAccountErrorCaptureFailure.unexpected(txError)
            }
        } else {
            let bookError = try #require(underlying as? OpalBase.Address.Book.Error)
            #expect(bookError == OpalBase.Address.Book.Error.insufficientFunds)
        }
    }

    private enum SpendValidationAccountErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    private static func captureSpendValidationAccountError(
        _ work: () async throws -> Void
    ) async throws -> OpalBase.Account.Error {
        do {
            try await work()
            throw SpendValidationAccountErrorCaptureFailure.didNotThrow
        } catch let error as OpalBase.Account.Error {
            return error
        } catch let error as SpendValidationAccountErrorCaptureFailure {
            throw error
        } catch {
            throw SpendValidationAccountErrorCaptureFailure.unexpected(error)
        }
    }
}
