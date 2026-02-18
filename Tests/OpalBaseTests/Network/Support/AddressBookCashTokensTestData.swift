import Foundation
@testable import OpalBase

enum AddressBookCashTokensTestData {
    static func makeAddressBook() async throws -> Address.Book {
        let mnemonic = try Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about",
        ])

        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))

        return try await Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 2
        )
    }
}
