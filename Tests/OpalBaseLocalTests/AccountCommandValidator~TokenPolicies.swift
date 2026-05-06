// AccountCommandValidator~TokenPolicies.swift

import Foundation
import Testing
@testable import OpalBase

extension AccountCommandValidator {
    @Test("prepareSpend rejects token recipients")
    func prepareSpendRejectsTokenRecipients() async throws {
        let account = try await AccountTestFixtures.makeAccount()

        let tokenCategory = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 1, count: 32))
        let tokenData = OpalBase.CashTokens.TokenData(category: tokenCategory, amount: 1, nft: nil)
        let recipientAddress = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let paymentAmount = try OpalBase.Satoshi(500)
        let payment = OpalBase.Account.Payment(recipients: [.init(address: recipientAddress,
                                                         amount: paymentAmount,
                                                         tokenData: tokenData)])

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected prepareSpend to reject token recipients")
        } catch let error as OpalBase.Account.Error {
            #expect(error == .paymentDoesNotSupportTokensUseTokenTransfer)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("prepareSpend rejects token unspent transaction outputs selection policy")
    func prepareSpendRejectsTokenUnspentTransactionOutputsSelectionPolicy() async throws {
        let account = try await AccountTestFixtures.makeAccount()

        let recipientAddress = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let paymentAmount = try OpalBase.Satoshi(500)
        let payment = OpalBase.Account.Payment(recipients: [.init(address: recipientAddress, amount: paymentAmount)],
                                      tokenInputPolicy: .allowTokenUTXOs)

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected prepareSpend to reject token unspent transaction outputs selection policy")
        } catch let error as OpalBase.Account.Error {
            #expect(error == .paymentCannotSpendTokenUTXOs)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("reserveSpend revalidates token policy when refreshing an existing reservation")
    func reserveSpendRevalidatesTokenPolicyForExistingReservation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let tokenUTXO = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 12_000,
            tokenData: AddressBookCashTokensTestData.makeTokenData(),
            hashByte: 0xE2
        )
        let changeEntry = try await addressBook.selectNextEntry(for: .change)

        let tokenReservation = try await addressBook.reserveSpend(
            utxos: [tokenUTXO],
            changeEntry: changeEntry,
            tokenSelectionPolicy: .allowTokenUTXOs
        )

        await #expect(throws: OpalBase.Address.Book.Error.utxoNotFound) {
            _ = try await addressBook.reserveSpend(
                utxos: [tokenUTXO],
                changeEntry: changeEntry,
                tokenSelectionPolicy: .excludeTokenUTXOs
            )
        }

        try await addressBook.releaseSpendReservation(tokenReservation, outcome: .cancelled)
    }
}
