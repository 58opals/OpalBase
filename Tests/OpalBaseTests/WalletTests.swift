import Testing
import Foundation
import CryptoKit
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
        await print(account.id.hexadecimalString)
        
        #expect(await wallet.accounts.count == 1, "Wallet should have one account after adding an account.")
    }
    
    @Test func testGetAccount() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.getAccount(unhardenedIndex: 0)
        
        await print(account.id.hexadecimalString)
    }
    
    @Test func testCalculateTotalBalance() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        try await wallet.addAccount(unhardenedIndex: 1)
        
        let totalBalance = try await wallet.getBalance()
        
        #expect(totalBalance.uint64 == 0, "Total balance should be 0 satoshis for a new wallet.")
    }
}

extension WalletTests {
    @Test mutating func testSnapshotSaveLoad() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let account = try await wallet.getAccount(unhardenedIndex: 0)
        let entry = await account.addressBook.receivingEntries[0]
        try await account.addressBook.updateCache(for: entry.address, with: try Satoshi(123))
        try await account.addressBook.mark(address: entry.address, isUsed: true)
        
        let key = SymmetricKey(size: .bits256)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        try await wallet.saveSnapshot(to: url, using: key)
        
        let newWallet = await Wallet(mnemonic: wallet.mnemonic)
        try await newWallet.loadSnapshot(from: url, using: key)
        
        let restoredAccount = try await newWallet.getAccount(unhardenedIndex: 0)
        let restoredEntry = await restoredAccount.addressBook.findEntry(for: entry.address)
        let restoredBalance = try await restoredAccount.addressBook.getBalanceFromCache(address: entry.address)
        
        #expect(restoredEntry?.isUsed == true, "Used flag should restore")
        #expect(restoredBalance?.uint64 == 123, "Balance should restore")
    }
    
    @Test mutating func testSnapshotSaveLoadWithoutKey() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let account = try await wallet.getAccount(unhardenedIndex: 0)
        let entry = await account.addressBook.receivingEntries[0]
        try await account.addressBook.updateCache(for: entry.address, with: try Satoshi(123))
        try await account.addressBook.mark(address: entry.address, isUsed: true)
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        try await wallet.saveSnapshot(to: url)
        
        let newWallet = await Wallet(mnemonic: wallet.mnemonic)
        try await newWallet.loadSnapshot(from: url)
        
        let restoredAccount = try await newWallet.getAccount(unhardenedIndex: 0)
        let restoredEntry = await restoredAccount.addressBook.findEntry(for: entry.address)
        let restoredBalance = try await restoredAccount.addressBook.getBalanceFromCache(address: entry.address)
        
        #expect(restoredEntry?.isUsed == true, "Used flag should restore")
        #expect(restoredBalance?.uint64 == 123, "Balance should restore")
    }
    
    @Test func testSnapshotRoundTrip() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        try await wallet.addAccount(unhardenedIndex: 1)
        
        let snap = await wallet.getSnapshot()
        let restoredWallet = try await Wallet(from: snap)
        let numberOfAccounts = await wallet.accounts.count
        
        #expect(await restoredWallet.id == wallet.id, "Wallet ID should persist")
        #expect(await restoredWallet.accounts.count == numberOfAccounts, "Account count should match")
        
        for index in 0 ..< numberOfAccounts {
            let original = await wallet.accounts[index]
            let recovered = await restoredWallet.accounts[index]
            #expect(await original.id == recovered.id, "Account IDs should match")
        }
    }
}
