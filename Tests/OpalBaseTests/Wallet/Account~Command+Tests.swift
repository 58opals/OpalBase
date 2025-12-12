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
    
    @Test("prepareSpend reserves spend resources until explicitly released")
    func testPrepareSpendReservesUntilReleased() async throws {
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
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 1, count: 32))
        let utxo = Transaction.Output.Unspent(
            value: 25_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([utxo])
        
        let recipientAddress = try Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let paymentAmount = try Satoshi(10_000)
        let payment = Account.Payment(recipients: [.init(address: recipientAddress, amount: paymentAmount)])
        
        let initialPlan = try await account.prepareSpend(payment)
        let initialChangeEntries = await addressBook.listEntries(for: .change)
        let initialFirstChange = initialChangeEntries.first { $0.derivationPath.index == 0 }
        #expect(initialFirstChange?.isUsed == true)
        #expect(initialFirstChange?.isReserved == true)
        let gapLimit = await addressBook.readGapLimit()
        let initialUnusedCount = initialChangeEntries.filter { !$0.isUsed }.count
        #expect(initialUnusedCount >= gapLimit)
        
        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected subsequent prepareSpend call to fail while reservation is active")
        } catch { }
        
        try await initialPlan.cancelReservation()
        
        let afterCancellationEntries = await addressBook.listEntries(for: .change)
        let restoredFirstChange = afterCancellationEntries.first { $0.derivationPath.index == 0 }
        #expect(restoredFirstChange?.isUsed == false)
        #expect(restoredFirstChange?.isReserved == false)
        let afterCancellationUnusedCount = afterCancellationEntries.filter { !$0.isUsed }.count
        #expect(afterCancellationUnusedCount >= gapLimit)
        
        let completedPlan = try await account.prepareSpend(payment)
        try await completedPlan.completeReservation()
        
        let afterCompletionEntries = await addressBook.listEntries(for: .change)
        let completedFirstChange = afterCompletionEntries.first { $0.derivationPath.index == 0 }
        #expect(completedFirstChange?.isUsed == true)
        #expect(completedFirstChange?.isReserved == false)
        let afterCompletionUnusedCount = afterCompletionEntries.filter { !$0.isUsed }.count
        #expect(afterCompletionUnusedCount >= gapLimit)
        
        let reusablePlan = try await account.prepareSpend(payment)
        try await reusablePlan.cancelReservation()
    }
    
    @Test("reserveNextReceivingEntry advances receiving entries")
    func testReserveNextReceivingEntryAdvancesReceivingEntries() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        
        let firstReservedEntry = try await account.reserveNextReceivingEntry()
        #expect(firstReservedEntry.derivationPath.index == 0)
        #expect(firstReservedEntry.isReserved == true)
        #expect(firstReservedEntry.isUsed == true)
        
        let secondReservedEntry = try await account.reserveNextReceivingEntry()
        #expect(secondReservedEntry.derivationPath.index == 1)
        #expect(secondReservedEntry.isReserved == true)
        #expect(secondReservedEntry.isUsed == true)
        #expect(secondReservedEntry.address != firstReservedEntry.address)
        
        let nextAvailableEntry = try await account.addressBook.selectNextEntry(for: .receiving)
        #expect(nextAvailableEntry.derivationPath.index == 2)
        #expect(nextAvailableEntry.isReserved == false)
        #expect(nextAvailableEntry.isUsed == false)
    }
}
