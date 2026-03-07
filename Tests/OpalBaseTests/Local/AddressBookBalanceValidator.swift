// AddressBookBalanceValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Address BookActor Balance", .tags(.unit, .address))
struct AddressBookBalanceValidator {
    @Test("calculateCachedTotalBalance throws when the sum exceeds the maximum supply")
    func calculateCachedTotalBalanceDetectsOverflow() async throws {
        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ]
        )
        let rootExtendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        let book = try await OpalBase.Address.Book(
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
        
        let maximumBalance = try OpalBase.Satoshi(OpalBase.Satoshi.maximumSatoshi)
        let singleSatoshi = try OpalBase.Satoshi(1)
        
        try await book.updateCachedBalance(for: firstAddress, balance: maximumBalance, timestamp: .now)
        try await book.updateCachedBalance(for: secondAddress, balance: singleSatoshi, timestamp: .now)
        
        await #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try await book.calculateCachedTotalBalance()
        }
    }
}

