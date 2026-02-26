import Foundation
import Testing
@testable import OpalBase

extension AccountCommandValidator {
    @Test("prepareSpend rejects token recipients")
    func prepareSpendRejectsTokenRecipients() async throws {
        let mnemonic = try MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = WalletActor(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)

        let tokenCategory = try CashTokensModel.CategoryIDModel(transactionOrderData: Data(repeating: 1, count: 32))
        let tokenData = CashTokensModel.TokenData(category: tokenCategory, amount: 1, nft: nil)
        let recipientAddress = try AddressModel("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let paymentAmount = try SatoshiModel(500)
        let payment = AccountActor.PaymentModel(recipients: [.init(address: recipientAddress,
                                                         amount: paymentAmount,
                                                         tokenData: tokenData)])

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected prepareSpend to reject token recipients")
        } catch let error as AccountActor.Error {
            #expect(error == .paymentDoesNotSupportTokensUseTokenTransfer)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("prepareSpend rejects token unspent transaction outputs selection policy")
    func prepareSpendRejectsTokenUnspentTransactionOutputsSelectionPolicy() async throws {
        let mnemonic = try MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = WalletActor(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)

        let recipientAddress = try AddressModel("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let paymentAmount = try SatoshiModel(500)
        let payment = AccountActor.PaymentModel(recipients: [.init(address: recipientAddress, amount: paymentAmount)],
                                      tokenSelectionPolicy: .allowTokenUTXOs)

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected prepareSpend to reject token unspent transaction outputs selection policy")
        } catch let error as AccountActor.Error {
            #expect(error == .paymentCannotSpendTokenUTXOs)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
