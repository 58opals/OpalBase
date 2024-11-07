import Testing
import Foundation
import SwiftFulcrum
@testable import OpalBase

@Suite("Wallet Tests")
struct WalletTests {
    var wallet: Wallet
    
    init() async throws {
        self.wallet = Wallet(mnemonic: try .init())
    }
}

extension WalletTests {
    @Test func testWalletIdentification() async throws {
        let mnemonic1 = try Mnemonic(words: ["then", "sword", "assault", "bench", "truck", "have", "later", "whisper", "circle", "double", "umbrella", "author"])
        let _ = try Mnemonic(words: ["board", "horn", "balcony", "supply", "throw", "water", "attract", "cannon", "action", "surround", "observe", "trade"])
        
        let wallet1 = Wallet(mnemonic: mnemonic1)
        let wallet2 = Wallet(mnemonic: mnemonic1)
        let wallet1ID = await wallet1.id
        let wallet2ID = await wallet2.id
        
        #expect(wallet1 == wallet2, "Wallets should have the same ID.")
        #expect(wallet1ID == wallet2ID, "Wallets should have the same ID.")
    }
}

extension WalletTests {
    @Test func testAddAccount() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.getAccount(unhardenedIndex: 0)
        
        #expect(await wallet.accounts.count == 1, "Wallet should have one account after adding an account.")
        #expect(account != nil, "Account at index 0 should not be nil.")
    }
    
    @Test func testGetAccount() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.getAccount(unhardenedIndex: 0)
        
        #expect(account != nil, "Account should be retrievable by index.")
    }
    
    @Test func testCalculateTotalBalance() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        try await wallet.addAccount(unhardenedIndex: 1)
        
        let totalBalance = try await wallet.getBalance()
        
        #expect(totalBalance.uint64 == 0, "Total balance should be 0 satoshis for a new wallet.")
    }
}
