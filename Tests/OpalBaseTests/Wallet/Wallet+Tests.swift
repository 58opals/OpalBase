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
}
