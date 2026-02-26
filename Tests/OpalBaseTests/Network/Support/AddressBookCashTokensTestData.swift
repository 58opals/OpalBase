import Foundation
@testable import OpalBase

enum AddressBookCashTokensTestData {
    static func makeAddressBook() async throws -> AddressModel.BookActor {
        let mnemonic = try MnemonicModel(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about",
        ])

        let rootExtendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))

        return try await AddressModel.BookActor(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 2
        )
    }
}
