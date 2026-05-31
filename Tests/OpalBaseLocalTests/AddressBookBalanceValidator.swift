// AddressBookBalanceValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Address.Book Balance", .tags(.unit, .address))
struct AddressBookBalanceValidator {
    @Test("calculateCachedTotalBalance throws when the sum exceeds the maximum supply")
    func calculateCachedTotalBalanceDetectsOverflow() async throws {
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        let book = try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 2
        )
        
        let receivingEntries = await book.listEntries(for: OpalBase.Key.DerivationPath.Usage.receiving)
        try #require(receivingEntries.count >= 2)
        
        let firstAddress = receivingEntries[0].address
        let secondAddress = receivingEntries[1].address
        
        let maximumBalance = try OpalBase.Satoshi(OpalBase.Satoshi.maximumSatoshi)
        let singleSatoshi = try OpalBase.Satoshi(1)
        
        try await book.updateCachedBalance(for: firstAddress, balance: maximumBalance, timestamp: .now)
        try await book.updateCachedBalance(for: secondAddress, balance: singleSatoshi, timestamp: .now)
        
        await #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try await book.calculateCachedTotalBalance()
        }
    }
}
