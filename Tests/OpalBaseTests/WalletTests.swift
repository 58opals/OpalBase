import Testing
import Foundation
import SwiftFulcrum
@testable import OpalBase

@Suite("Wallet Tests")
struct WalletTests {
    let mnemonic: Mnemonic
    var wallet: Wallet
    
    init() async throws {
        self.mnemonic = try Mnemonic()
        self.wallet = Wallet(mnemonic: mnemonic)
    }
}

extension WalletTests {
    
    @Test mutating func testAddAccount() async throws {
        try wallet.addAccount(unhardenedIndex: 0)
        
        #expect(wallet.accounts.count == 1, "Wallet should have one account after adding an account.")
        #expect(try wallet.getAccount(unhardenedIndex: 0) != nil, "Account at index 0 should not be nil.")
    }
    
    @Test mutating func testGetAccount() async throws {
        try wallet.addAccount(unhardenedIndex: 0)
        let account = try wallet.getAccount(unhardenedIndex: 0)
        
        #expect(account != nil, "Account should be retrievable by index.")
    }
    
    @Test mutating func testCalculateTotalBalance() async throws {
        try wallet.addAccount(unhardenedIndex: 0)
        try wallet.addAccount(unhardenedIndex: 1)
        
        let totalBalance = try wallet.getBalance()
        
        #expect(totalBalance.uint64 == 0, "Total balance should be 0 satoshis for a new wallet.")
    }
}
