import Foundation
import Testing
@testable import OpalBase

@Suite("Address Book UTXO Selection", .tags(.unit, .wallet))
struct AddressBookUTXOSuite {
    @Test("greedy largest-first does not double-count fees", .tags(.unit, .wallet))
    func greedySelectionDoesNotDoubleCountFees() async throws {
        let mnemonic = try Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about"
        ])
        let rootKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let account = try DerivationPath.Account(rawIndexInteger: 0)
        
        let subject = try await Address.Book(
            rootExtendedPrivateKey: rootKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            gapLimit: 1,
            cacheValidityDuration: 60
        )
        
        let hash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let highValue = Transaction.Output.Unspent(
            value: 5_000,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 0
        )
        let topUp = Transaction.Output.Unspent(
            value: 500,
            lockingScript: Data(),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 1
        )
        
        await subject.addUTXOs([highValue, topUp])
        
        let selection = try await subject.selectUTXOs(
            targetAmount: try Satoshi(5_000),
            feePerByte: 1,
            strategy: .greedyLargestFirst
        )
        
        #expect(Set(selection) == Set([highValue, topUp]))
    }
}
