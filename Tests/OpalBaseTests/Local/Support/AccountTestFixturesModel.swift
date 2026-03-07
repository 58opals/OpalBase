// AccountTestFixturesModel.swift

import Foundation
@testable import OpalBase

enum AccountTestFixturesModel {
    static let mnemonicWords: [String] = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about"
    ]

    static let standardAddressString = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    static let tokenAwareAddressString = "bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"

    static func makeMnemonic(passphrase: String = "") throws -> OpalBase.Mnemonic {
        try OpalBase.Mnemonic(words: mnemonicWords, passphrase: passphrase)
    }

    static func makeWallet(
        accountIndices: [UInt32] = [0],
        passphrase: String = ""
    ) async throws -> OpalBase.Wallet {
        let wallet = OpalBase.Wallet(mnemonic: try makeMnemonic(passphrase: passphrase))
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
        usage: OpalBase.DerivationPath.UsageModel = .receiving,
        hashByte: UInt8,
        outputIndex: UInt32 = 0
    ) async throws -> OpalBase.Transaction.OutputModel.UnspentModel {
        let addressBook = await account.addressBook
        let entry = try await addressBook.selectNextEntry(for: usage)
        let output = OpalBase.Transaction.OutputModel.UnspentModel(
            value: value,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: makeHash(byte: hashByte),
            previousTransactionOutputIndex: outputIndex
        )
        await addressBook.addUTXOs([output])
        return output
    }

    static func makeHash(byte: UInt8) -> OpalBase.Transaction.HashModel {
        OpalBase.Transaction.HashModel(naturalOrder: Data(repeating: byte, count: 32))
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

