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

    static func makeMnemonic(passphrase: String = "") throws -> MnemonicModel {
        try MnemonicModel(words: mnemonicWords, passphrase: passphrase)
    }

    static func makeWallet(
        accountIndices: [UInt32] = [0],
        passphrase: String = ""
    ) async throws -> WalletActor {
        let wallet = WalletActor(mnemonic: try makeMnemonic(passphrase: passphrase))
        for index in accountIndices {
            try await wallet.addAccount(unhardenedIndex: index)
        }
        return wallet
    }

    static func makeAccount(
        unhardenedIndex: UInt32 = 0,
        passphrase: String = ""
    ) async throws -> AccountActor {
        let wallet = try await makeWallet(accountIndices: [unhardenedIndex], passphrase: passphrase)
        return try await wallet.fetchAccount(at: unhardenedIndex)
    }

    static func addUnspentOutput(
        to account: AccountActor,
        value: UInt64,
        tokenData: CashTokensModel.TokenData? = nil,
        usage: DerivationPathModel.UsageModel = .receiving,
        hashByte: UInt8,
        outputIndex: UInt32 = 0
    ) async throws -> TransactionModel.OutputModel.UnspentModel {
        let addressBook = await account.addressBook
        let entry = try await addressBook.selectNextEntry(for: usage)
        let output = TransactionModel.OutputModel.UnspentModel(
            value: value,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: makeHash(byte: hashByte),
            previousTransactionOutputIndex: outputIndex
        )
        await addressBook.addUTXOs([output])
        return output
    }

    static func makeHash(byte: UInt8) -> TransactionModel.HashModel {
        TransactionModel.HashModel(naturalOrder: Data(repeating: byte, count: 32))
    }

    static func makeHistoryEntry(
        hashByte: UInt8,
        blockHeight: Int = 1,
        fee: UInt64? = nil
    ) -> NetworkModel.TransactionHistoryEntryModel {
        let identifier = makeHash(byte: hashByte).reverseOrder.hexadecimalString
        return NetworkModel.TransactionHistoryEntryModel(
            transactionIdentifier: identifier,
            blockHeight: blockHeight,
            fee: fee
        )
    }
}

