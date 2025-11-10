import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet", .tags(.unit, .wallet))
struct WalletTests {
    @Test("fetchAccount locates accounts regardless of insertion order")
    func testFetchAccountLocatesOutOfOrderAccountIndices() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 3)
        try await wallet.addAccount(unhardenedIndex: 0)
        
        let thirdAccount = try await wallet.fetchAccount(at: 3)
        let zerothAccount = try await wallet.fetchAccount(at: 0)
        
        #expect(await thirdAccount.unhardenedIndex == 3)
        #expect(await zerothAccount.unhardenedIndex == 0)
    }
    
    @Test("fetchAccount throws when the index is missing")
    func testFetchAccountRejectsMissingAccount() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        
        await #expect(throws: Wallet.Error.cannotFetchAccount(index: 0)) {
            _ = try await wallet.fetchAccount(at: 0)
        }
    }
    
    @Test("fetchAccount rejects unknown account indices")
    func testFetchAccountRejectsUnknownAccountIndices() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)
        
        let missingIndex: UInt32 = 7
        
        await #expect(throws: Wallet.Error.cannotFetchAccount(index: missingIndex)) {
            _ = try await wallet.fetchAccount(at: missingIndex)
        }
    }
}
