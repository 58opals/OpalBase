import Testing
import Foundation
import SwiftFulcrum
@testable import OpalBase

@Suite("Account Tests")
struct AccountTests {
    var account: Account
    
    init() async throws {
        let wallet = Wallet(mnemonic: try .init())
        try await wallet.addAccount(unhardenedIndex: 0)
        self.account = try await wallet.getAccount(unhardenedIndex: 0)
        
        let fulcrum = try await account.fulcrumPool.getFulcrum()
        try await fulcrum.start()
    }
}

extension AccountTests {
    @Test func testAccountIdentification() async throws {
        let mnemonic1 = try Mnemonic(words: ["then", "sword", "assault", "bench", "truck", "have", "later", "whisper", "circle", "double", "umbrella", "author"])
        let _ = try Mnemonic(words: ["board", "horn", "balcony", "supply", "throw", "water", "attract", "cannon", "action", "surround", "observe", "trade"])
        
        let wallet1 = Wallet(mnemonic: mnemonic1)
        let wallet2 = Wallet(mnemonic: mnemonic1)
        
        let wallet1ID = await wallet1.id
        let wallet2ID = await wallet2.id
        
        #expect(wallet1 == wallet2, "Wallets should have the same ID.")
        #expect(wallet1ID == wallet2ID, "Wallets should have the same ID.")
        
        try await wallet1.addAccount(unhardenedIndex: 0)
        try await wallet2.addAccount(unhardenedIndex: 0)
        
        let account0FromWallet1 = try await wallet1.getAccount(unhardenedIndex: 0)
        let account0FromWallet2 = try await wallet2.getAccount(unhardenedIndex: 0)
        
        let account0FromWallet1ID = await account0FromWallet1.id
        let account0FromWallet2ID = await account0FromWallet2.id
        
        #expect(account0FromWallet1 == account0FromWallet2, "Accounts should have the same ID.")
        #expect(account0FromWallet1ID == account0FromWallet2ID, "Accounts should have the same ID.")
    }
}

extension AccountTests {
    @Test func testAccountInitialization() async throws {
        await print(account.id.hexadecimalString)
        await print(account.addressBook)
    }
    
    @Test mutating func testCalculateBalance() async throws {
        let balance = try await account.calculateBalance()
        
        #expect(balance.uint64 >= 0, "Account balance should be at least 0.")
        
        print(balance)
    }
    
    @Test mutating func testParallelBalancePerformance() async throws {
        func sequentialBalance() async throws -> Satoshi {
            var total: UInt64 = 0
            let addresses = await (account.addressBook.receivingEntries + account.addressBook.changeEntries).map(\.address)
            let fulcrum = try await account.fulcrumPool.getFulcrum()
            for address in addresses {
                total += try await account.addressBook.getBalanceFromBlockchain(address: address, fulcrum: fulcrum).uint64
            }
            return try Satoshi(total)
        }
        
        let clock = ContinuousClock()
        let seqStart = clock.now
        let seqBalance = try await sequentialBalance()
        let sequentialDuration = seqStart.duration(to: clock.now)
        
        let parStart = clock.now
        let parallelBalance = try await account.calculateBalance()
        let parallelDuration = parStart.duration(to: clock.now)
        
        #expect(seqBalance == parallelBalance, "Parallel and sequential balances should match.")
        #expect(parallelDuration < sequentialDuration, "Parallel computation should be faster.")
    }
    
    @Test mutating func testSendTransaction() async {
        do {
            let recipientAddress = try Address("bitcoincash:qr4yz562852sglpmjmxvktrph5syts064yjadyqvc8")
            let transactionHash = try await account.send(
                [
                    (value: .init(565), recipientAddress: recipientAddress)
                ]
            )
            
            print("The new transaction \(transactionHash.reversedData.hexadecimalString) is successfully created.")
            
            #expect(transactionHash.count == 32, "Transaction hash should be 32 bytes.")
        } catch {
            print(error)
        }
    }
}
