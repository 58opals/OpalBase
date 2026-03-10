// AddressBookCashTokensSupport.swift

import Foundation
import OpalCrypto
@testable import OpalBase

public enum AddressBookCashTokensSupport {
    public static func makeAddressBook() async throws -> OpalBase.Address.Book {
        let mnemonic = try OpalCrypto.Key.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about",
            ].map(OpalCrypto.Key.Mnemonic.Word.init)
        )
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivateKey.root(seed: mnemonic.deriveSeed())

        return try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 2
        )
    }
}
