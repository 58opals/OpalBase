import XCTest
@testable import OpalBase

final class AccountTests: XCTestCase {
    var account: Account!
    
    override func setUp() async throws {
        try await super.setUp()
        
        let mnemonic = try Mnemonic()
        
        var wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        self.account = try wallet.getAccount(unhardenedIndex: 0)
    }
    
    override func tearDown() {
        account = nil
        super.tearDown()
    }
}

extension AccountTests {
    func testAccountInitialization() async throws {
        XCTAssertNotNil(account.addressBook, "Address book should be initialized.")
        XCTAssertNotNil(account.fulcrum, "Fulcrum instance should be initialized.")
    }
    
    func testCalculateBalance() async throws {
        let balance = try await account.calculateBalance()
        
        XCTAssertEqual(balance, try Satoshi(0))
    }

    func testSendTransaction() async throws {
        let recipientAddress = try Address("bitcoincash:qr4yz562852sglpmjmxvktrph5syts064yjadyqvc8")
        let transactionHash = try await account.send(
            [
                (value: .init(565), recipientAddress: recipientAddress)
            ]
        )
        
        print("The new transaction \(transactionHash.reversedData.hexadecimalString) is successfully created.")
        
        XCTAssertEqual(transactionHash.count, 32)
    }
}
