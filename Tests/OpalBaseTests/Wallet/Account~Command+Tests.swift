import Foundation
import Testing
@testable import OpalBase

@Suite("Account Command", .tags(.unit, .wallet))
struct AccountCommandTests {
    @Test("prepareSpend reports insufficient funds when sweep-all shortfall occurs")
    func testPrepareSpendReportsShortfallForSweepAllCoinSelection() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let utxo = Transaction.Output.Unspent(
            value: 1_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([utxo])
        
        let recipientAddress = try Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let paymentAmount = try Satoshi(2_000)
        let payment = Account.Payment(
            recipients: [.init(address: recipientAddress, amount: paymentAmount)],
            coinSelection: .sweepAll
        )
        
        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected prepareSpend to surface insufficient funds")
        } catch let error as Account.Error {
            switch error {
            case .coinSelectionFailed(let underlyingError):
                guard let transactionError = underlyingError as? Transaction.Error else {
                    Issue.record("Expected Transaction.Error but received \(type(of: underlyingError))")
                    return
                }
                
                switch transactionError {
                case .insufficientFunds(required: let requiredAmount):
                    #expect(requiredAmount == 1_000)
                default:
                    Issue.record("Expected insufficient funds but received \(transactionError)")
                }
            default:
                Issue.record("Expected coinSelectionFailed but received \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
