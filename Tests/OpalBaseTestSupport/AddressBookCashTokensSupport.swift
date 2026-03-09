// AddressBookCashTokensSupport.swift

import Foundation
@testable import OpalBase

public enum AddressBookCashTokensSupport {
    public static func makeAddressBook() async throws -> OpalBase.Address.Book {
        let mnemonic = try OpalBase.Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about",
        ])

        let rootExtendedPrivateKey = OpalBase.PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))

        return try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 2
        )
    }
}
