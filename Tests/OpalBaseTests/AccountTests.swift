import XCTest
@testable import OpalBase

final class AccountTests: XCTestCase {
    var account: Account!
    
    override func setUp() async throws {
        try await super.setUp()
        
        let mnemonic = try Mnemonic()
        
        var wallet = Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(index: 0)
        
        self.account = wallet.getAccount(index: 0)
    }
    
    override func tearDown() {
        account = nil
        super.tearDown()
    }
}

extension AccountTests {
    func testAccountInitialization() async throws {
        let accountIndex: UInt32 = 0
        
        XCTAssertEqual(account.accountIndex, accountIndex, "Account index should match the initialized value.")
        XCTAssertNotNil(account.addressBook, "Address book should be initialized.")
        XCTAssertNotNil(account.fulcrum, "Fulcrum instance should be initialized.")
    }
    
    func testCalculateBalance() async throws {
        let balance = try await account.calculateBalance()
        
        XCTAssertEqual(balance, try Satoshi(0))
    }

    func testSendTransaction() async throws {
        let receivingAddress = try Address("qrtlrv292x9dz5a24wg6a2a7pntu8am7hyyjjwy0hk")
        let transactionHash = try await account.send([(value: .init(565), address: receivingAddress)])
    }
}
