import XCTest
@testable import OpalBase

final class WalletTests: XCTestCase {
    var mnemonic: Mnemonic!
    var wallet: Wallet!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        self.mnemonic = try Mnemonic()
        self.wallet = Wallet(mnemonic: mnemonic)
    }
    
    override func tearDown() {
        wallet = nil
        mnemonic = nil
        super.tearDown()
    }
}
 
extension WalletTests {
    func testAddAccount() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        
        XCTAssertEqual(wallet.accounts.count, 1, "Wallet should have one account after adding an account.")
        XCTAssertNotNil(try wallet.getAccount(unhardenedIndex: 0), "Account at index 0 should not be nil.")
    }
    
    func testGetAccount() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try wallet.getAccount(unhardenedIndex: 0)
        
        XCTAssertNotNil(account, "Account should be retrievable by index.")
    }
    
    func testCalculateTotalBalance() async throws {
        try await wallet.addAccount(unhardenedIndex: 0)
        try await wallet.addAccount(unhardenedIndex: 1)
        
        let totalBalance = try wallet.getBalance()
        
        XCTAssertEqual(totalBalance, try Satoshi(0))
    }
}
