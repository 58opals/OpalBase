// AddressBookCashTokensSupport.swift

import OpalCrypto

public enum AddressBookCashTokensSupport {
    public static func makeRootExtendedPrivateKey() throws -> OpalCrypto.Key.ExtendedPrivate {
        let mnemonic = try OpalCrypto.Key.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about",
            ].map(OpalCrypto.Key.Mnemonic.Word.init)
        )
        return try OpalCrypto.Key.ExtendedPrivate.root(seed: mnemonic.deriveSeed())
    }
}
