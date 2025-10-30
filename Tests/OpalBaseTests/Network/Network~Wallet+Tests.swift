import Foundation
import Testing
@testable import OpalBase

@Suite("Network.FulcrumSession Wallet Extensions", .tags(.unit, .wallet, .network))
struct NetworkFulcrumSessionWalletExtensionTests {
    @Test("createAccount returns the added account")
    func testCreateAccountReturnsAccount() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        let session = try await Network.FulcrumSession()
        
        let account = try await session.createAccount(for: wallet, at: 0)
        let fetchedAccount = try await wallet.fetchAccount(at: 0)
        let accountCount = await wallet.numberOfAccounts
        let walletDerivationPath = await wallet.derivationPath
        let accountPurpose = await account.purpose
        let accountCoinType = await account.coinType
        
        #expect(await account.id == fetchedAccount.id)
        #expect(accountCount == 1)
        #expect(accountPurpose == walletDerivationPath.purpose)
        #expect(accountCoinType == walletDerivationPath.coinType)
    }
    
    @Test("computeCachedBalance returns the account cache total")
    func testComputeCachedBalanceForAccount() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        let session = try await Network.FulcrumSession()
        let account = try await session.createAccount(for: wallet, at: 0)
        
        let entry = try await account.addressBook.selectNextEntry(for: .receiving, fetchBalance: false)
        try await account.addressBook.updateCache(for: entry.address, with: try Satoshi(1_500))
        
        let balance = try await session.computeCachedBalance(for: account)
        #expect(balance.uint64 == 1_500)
    }
    
    @Test("computeCachedBalance aggregates across wallet accounts")
    func testComputeCachedBalanceForWallet() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        let session = try await Network.FulcrumSession()
        
        let firstAccount = try await session.createAccount(for: wallet, at: 0)
        let secondAccount = try await session.createAccount(for: wallet, at: 1)
        
        let firstEntry = try await firstAccount.addressBook.selectNextEntry(for: .receiving, fetchBalance: false)
        try await firstAccount.addressBook.updateCache(for: firstEntry.address, with: try Satoshi(2_000))
        
        let secondEntry = try await secondAccount.addressBook.selectNextEntry(for: .receiving, fetchBalance: false)
        try await secondAccount.addressBook.updateCache(for: secondEntry.address, with: try Satoshi(3_250))
        
        let total = try await session.computeCachedBalance(for: wallet)
        #expect(total.uint64 == 5_250)
    }
}
