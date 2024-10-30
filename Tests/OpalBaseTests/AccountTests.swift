import Testing
import Foundation
import SwiftFulcrum
@testable import OpalBase

@Suite("Account Tests")
struct AccountTests {
    var account: Account
    
    init() async throws {
        var wallet = Wallet(mnemonic: try .init())
        try wallet.addAccount(unhardenedIndex: 0)
        self.account = try wallet.getAccount(unhardenedIndex: 0)
        
        try await account.fulcrum.start()
    }
}

extension AccountTests {
    @Test func testAccountInitialization() async throws {
        #expect(account != nil, "Account should be initialized.")
        #expect(account.addressBook != nil, "Address book should be initialized.")
        #expect(account.fulcrum != nil, "Fulcrum instance should be initialized.")
    }
    
    @Test mutating func testCalculateBalance() async throws {
        let balance = try await account.calculateBalance()
        
        #expect(balance.uint64 >= 0, "Account balance should be at least 0.")
    }

    @Test mutating func testSendTransaction() async throws {
        let recipientAddress = try Address("bitcoincash:qr4yz562852sglpmjmxvktrph5syts064yjadyqvc8")
        let transactionHash = try await account.send(
            [
                (value: .init(565), recipientAddress: recipientAddress)
            ]
        )
        
        print("The new transaction \(transactionHash.reversedData.hexadecimalString) is successfully created.")
        
        #expect(transactionHash.count == 32, "Transaction hash should be 32 bytes.")
    }
}
