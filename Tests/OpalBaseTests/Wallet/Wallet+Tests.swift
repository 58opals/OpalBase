import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet", .tags(.unit, .wallet))
struct WalletTests {
    @Test("calculateBalance aggregates cached balances across accounts")
    func testCalculateBalanceAggregatesAccounts() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0)
        try await wallet.addAccount(unhardenedIndex: 1)
        
        let firstAccount = try await wallet.fetchAccount(at: 0)
        let secondAccount = try await wallet.fetchAccount(at: 1)
        
        let firstReceivingEntry = try await firstAccount.addressBook.selectNextEntry(for: .receiving)
        try await firstAccount.addressBook.updateCachedBalance(for: firstReceivingEntry.address,
                                                               balance: Satoshi(1_000),
                                                               timestamp: .now)
        
        let secondReceivingEntry = try await secondAccount.addressBook.selectNextEntry(for: .receiving)
        try await secondAccount.addressBook.updateCachedBalance(for: secondReceivingEntry.address,
                                                                balance: Satoshi(2_500),
                                                                timestamp: .now)
        
        let balance = try await wallet.calculateBalance()
        #expect(balance.uint64 == 3_500)
    }
    
    @Test("calculateBalance returns zero when wallet has no accounts")
    func testCalculateBalanceWithoutAccountsReturnsZero() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        
        let balance = try await wallet.calculateBalance()
        let zeroBalance = try Satoshi(0)
        #expect(balance == zeroBalance)
    }
    
    @Test("fetchAccount locates accounts regardless of insertion order")
    func testFetchAccountLocatesOutOfOrderAccountIndices() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 3)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let thirdAccount = try await wallet.fetchAccount(at: 3)
        let zerothAccount = try await wallet.fetchAccount(at: 0)
        
        #expect(await thirdAccount.unhardenedIndex == 3)
        #expect(await zerothAccount.unhardenedIndex == 0)
    }
}
