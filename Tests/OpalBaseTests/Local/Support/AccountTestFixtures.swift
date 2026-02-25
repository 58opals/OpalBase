import Foundation
@testable import OpalBase

enum AccountTestFixtures {
    static let mnemonicWords: [String] = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about"
    ]

    static let standardAddressString = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    static let tokenAwareAddressString = "bitcoincash:zpm2qsznhks23z7629mms6s4cwef74vcwvrqekrq9w"

    static func makeMnemonic(passphrase: String = "") throws -> Mnemonic {
        try Mnemonic(words: mnemonicWords, passphrase: passphrase)
    }

    static func makeWallet(
        accountIndices: [UInt32] = [0],
        passphrase: String = ""
    ) async throws -> Wallet {
        let wallet = Wallet(mnemonic: try makeMnemonic(passphrase: passphrase))
        for index in accountIndices {
            try await wallet.addAccount(unhardenedIndex: index)
        }
        return wallet
    }

    static func makeAccount(
        unhardenedIndex: UInt32 = 0,
        passphrase: String = ""
    ) async throws -> Account {
        let wallet = try await makeWallet(accountIndices: [unhardenedIndex], passphrase: passphrase)
        return try await wallet.fetchAccount(at: unhardenedIndex)
    }

    static func addUnspentOutput(
        to account: Account,
        value: UInt64,
        tokenData: CashTokens.TokenData? = nil,
        usage: DerivationPath.Usage = .receiving,
        hashByte: UInt8,
        outputIndex: UInt32 = 0
    ) async throws -> Transaction.Output.Unspent {
        let addressBook = await account.addressBook
        let entry = try await addressBook.selectNextEntry(for: usage)
        let output = Transaction.Output.Unspent(
            value: value,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: makeHash(byte: hashByte),
            previousTransactionOutputIndex: outputIndex
        )
        await addressBook.addUTXOs([output])
        return output
    }

    static func makeHash(byte: UInt8) -> Transaction.Hash {
        Transaction.Hash(naturalOrder: Data(repeating: byte, count: 32))
    }

    static func makeHistoryEntry(
        hashByte: UInt8,
        blockHeight: Int = 1,
        fee: UInt64? = nil
    ) -> Network.TransactionHistoryEntry {
        let identifier = makeHash(byte: hashByte).reverseOrder.hexadecimalString
        return Network.TransactionHistoryEntry(
            transactionIdentifier: identifier,
            blockHeight: blockHeight,
            fee: fee
        )
    }
}
