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
    func testWalletInitialization() throws {
        XCTAssertEqual(wallet.purpose, .bip44, "Wallet purpose should be bip44 by default.")
        XCTAssertEqual(wallet.coinType, .bitcoinCash, "Wallet coin type should be bitcoinCash by default.")
        XCTAssertEqual(wallet.accounts.count, 0, "Wallet should have no accounts initially.")
    }
    
    func testAddAccount() async throws {
        try await wallet.addAccount(index: 0)
        
        XCTAssertEqual(wallet.accounts.count, 1, "Wallet should have one account after adding an account.")
        XCTAssertNotNil(wallet.getAccount(index: 0), "Account at index 0 should not be nil.")
    }
    
    func testGetAccount() async throws {
        try await wallet.addAccount(index: 0)
        let account = wallet.getAccount(index: 0)
        
        XCTAssertNotNil(account, "Account should be retrievable by index.")
        XCTAssertEqual(account?.accountIndex, 0, "Account index should match the one used to create it.")
    }
    
    func testCalculateTotalBalance() async throws {
        try await wallet.addAccount(index: 0)
        try await wallet.addAccount(index: 1)
        
        let totalBalance = try wallet.getBalance()
        
        XCTAssertEqual(totalBalance, try Satoshi(0))
    }
}
