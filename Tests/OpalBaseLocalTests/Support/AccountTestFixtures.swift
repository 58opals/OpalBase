// AccountTestFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalBase

enum AccountTestFixtures {
    static let mnemonicWords: [String] = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about"
    ]

    static let standardAddressString = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    static let tokenAwareAddressString = "bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"

    static func makeMnemonic(
        words: [String] = mnemonicWords,
        passphrase _: String = ""
    ) throws -> OpalCrypto.Key.Mnemonic {
        try OpalCrypto.Key.Mnemonic(words: words.map(OpalCrypto.Key.Mnemonic.Word.init))
    }

    static func makeWallet(
        accountIndices: [UInt32] = [0],
        mnemonicWords: [String] = mnemonicWords,
        passphrase: String = ""
    ) async throws -> OpalBase.Wallet {
        let wallet = try OpalBase.Wallet(
            mnemonic: makeMnemonic(words: mnemonicWords, passphrase: passphrase),
            passphrase: passphrase
        )
        for index in accountIndices {
            try await wallet.addAccount(unhardenedIndex: index)
        }
        return wallet
    }

    static func makeAccount(
        unhardenedIndex: UInt32 = 0,
        passphrase: String = ""
    ) async throws -> OpalBase.Account {
        let wallet = try await makeWallet(accountIndices: [unhardenedIndex], passphrase: passphrase)
        return try await wallet.fetchAccount(at: unhardenedIndex)
    }

    static func addUnspentOutput(
        to account: OpalBase.Account,
        value: UInt64,
        tokenData: OpalBase.CashTokens.TokenData? = nil,
        usage: OpalBase.Key.DerivationPath.Usage = .receiving,
        hashByte: UInt8,
        outputIndex: UInt32 = 0
    ) async throws -> OpalBase.Transaction.Output.Unspent {
        let addressBook = await account.addressBook
        let entry = try await addressBook.selectNextEntry(for: usage)
        let output = OpalBase.Transaction.Output.Unspent(
            value: value,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: makeHash(byte: hashByte),
            previousTransactionOutputIndex: outputIndex
        )
        await addressBook.addUTXOs([output])
        return output
    }

    static func makeHash(byte: UInt8) -> OpalBase.Transaction.Hash {
        OpalBase.Transaction.Hash(naturalOrder: Data(repeating: byte, count: 32))
    }

    static func makeHistoryEntry(
        hashByte: UInt8,
        blockHeight: Int = 1,
        fee: UInt64? = nil
    ) -> OpalBase.Network.TransactionHistoryEntry {
        let identifier = makeHash(byte: hashByte).reverseOrder.hexadecimalString
        return OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: identifier,
            blockHeight: blockHeight,
            fee: fee
        )
    }
}
