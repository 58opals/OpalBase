import Foundation
import Testing
@testable import OpalBase

@Suite("AddressModel BookActor Balance", .tags(.unit, .address))
struct AddressBookBalanceValidator {
    @Test("calculateCachedTotalBalance throws when the sum exceeds the maximum supply")
    func calculateCachedTotalBalanceDetectsOverflow() async throws {
        let mnemonic = try MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        let book = try await AddressModel.BookActor(
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
        
        let maximumBalance = try SatoshiModel(SatoshiModel.maximumSatoshi)
        let singleSatoshi = try SatoshiModel(1)
        
        try await book.updateCachedBalance(for: firstAddress, balance: maximumBalance, timestamp: .now)
        try await book.updateCachedBalance(for: secondAddress, balance: singleSatoshi, timestamp: .now)
        
        await #expect(throws: SatoshiModel.Error.exceedsMaximumAmount) {
            _ = try await book.calculateCachedTotalBalance()
        }
    }
}
