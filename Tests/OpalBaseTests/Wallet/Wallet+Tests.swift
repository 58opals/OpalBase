import Testing
@testable import OpalBase

@Suite("Wallet", .tags(.unit, .wallet))
struct WalletTests {
    @Test("calculateBalance aggregates cached balances across accounts")
    func testCalculateBalanceAggregatesAccounts() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let wallet = Wallet(mnemonic: mnemonic)

        try await wallet.addAccount(unhardenedIndex: 0)
        try await wallet.addAccount(unhardenedIndex: 1)

        let firstAccount = try await wallet.fetchAccount(at: 0)
        let secondAccount = try await wallet.fetchAccount(at: 1)

        let firstReceivingEntry = try await firstAccount.addressBook.selectNextEntry(for: .receiving, shouldFetchBalance: false)
        try await firstAccount.addressBook.updateCache(for: firstReceivingEntry.address, with: Satoshi(1_000))

        let secondReceivingEntry = try await secondAccount.addressBook.selectNextEntry(for: .receiving, shouldFetchBalance: false)
        try await secondAccount.addressBook.updateCache(for: secondReceivingEntry.address, with: Satoshi(2_500))

        let balance = try await wallet.calculateBalance()
        #expect(balance.uint64 == 3_500)
    }
}
