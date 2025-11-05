import Foundation
import Testing
@testable import OpalBase

@Suite("Address Book Balance", .tags(.unit, .address))
struct AddressBookBalanceTests {
    @Test("calculateCachedTotalBalance throws when the sum exceeds the maximum supply")
    func testCalculateCachedTotalBalanceDetectsOverflow() async throws {
        let mnemonic = try Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let book = try await Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 2
        )
        
        let receivingEntries = await book.listEntries(for: .receiving)
        #expect(receivingEntries.count >= 2)
        
        let firstAddress = receivingEntries[0].address
        let secondAddress = receivingEntries[1].address
        
        let maximumBalance = try Satoshi(Satoshi.maximumSatoshi)
        let singleSatoshi = try Satoshi(1)
        
        try await book.updateCachedBalance(for: firstAddress, balance: maximumBalance, timestamp: .now)
        try await book.updateCachedBalance(for: secondAddress, balance: singleSatoshi, timestamp: .now)
        
        await #expect(throws: Satoshi.Error.exceedsMaximumAmount) {
            _ = try await book.calculateCachedTotalBalance()
        }
    }
}
