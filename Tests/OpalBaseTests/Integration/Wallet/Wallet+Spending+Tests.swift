import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet Fulcrum Spending", .tags(.integration, .network, .fulcrum, .transaction))
struct WalletFulcrumSpendingSuite {
    @Test("fetches zero balance for fresh address", .tags(.integration, .network, .fulcrum, .transaction))
    func fetchesZeroBalanceForFreshAddress() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        
        let mnemonic = try Mnemonic(length: .short)
        let wallet = Wallet(mnemonic: mnemonic)
        
        try await wallet.addAccount(unhardenedIndex: 0, fulcrumServerURLs: [endpoint])
        
        let account = try await wallet.fetchAccount(at: 0)
        let receivingEntry = try await account.addressBook.selectNextEntry(for: .receiving)
        
        let node = try await account.fulcrumPool.acquireNode()
        let balance = try await account.addressBook.fetchBalance(for: receivingEntry.address, using: node)
        #expect(balance.uint64 == 0)
        
        let cachedBalance = try await account.addressBook.calculateCachedTotalBalance()
        #expect(cachedBalance.uint64 == 0)
    }
    
    @Test("builds raw transaction from single UTXO", .tags(.integration, .network, .fulcrum, .transaction))
    func buildsRawTransactionFromSingleUTXO() async throws {
        guard Environment.network else { return }
        let endpoint = try #require(Environment.fulcrumURL)
        print(endpoint)
        
        let wif = "L3uV4ompYyuMTg2YyLJpfaAqa4oHNq6x3Wa4iK1CkyxwyuEiYXXu"
        let privateKey = try PrivateKey(wif: wif)
        let publicKey = try PublicKey(privateKey: privateKey)
        let publicKeyHash = PublicKey.Hash(publicKey: publicKey)
        let lockingScript = Script.p2pkh_OPCHECKSIG(hash: publicKeyHash).data
        
        let previousTransactionHash = try Transaction.Hash(naturalOrder: Data(hexString: "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"))
        let utxo = Transaction.Output.Unspent(value: 150_000,
                                              lockingScript: lockingScript,
                                              previousTransactionHash: previousTransactionHash,
                                              previousTransactionOutputIndex: 2)
        let utxoPrivateKeyPairs: [Transaction.Output.Unspent: PrivateKey] = [utxo: privateKey]
        
        let recipientVectorHashData = try Data(hexString: "4e22f7d2617323d696130dbe8ab44727042d15b5")
        let recipientVectorHash = PublicKey.Hash(recipientVectorHashData)
        let recipientAddress = try Address(script: .p2pkh_OPCHECKSIG(hash: recipientVectorHash))
        let recipientAmount: UInt64 = 50_000
        let recipientOutput = Transaction.Output(value: recipientAmount, address: recipientAddress)
        
        let changeAddress = try Address(script: .p2pkh_OPCHECKSIG(hash: publicKeyHash))
        let initialChangeValue = utxo.value - recipientAmount
        let changeOutput = Transaction.Output(value: initialChangeValue, address: changeAddress)
        
        let transaction = try Transaction.build(version: 2,
                                                utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                                                recipientOutputs: [recipientOutput],
                                                changeOutput: changeOutput,
                                                feePerByte: 1)
        
        #expect(transaction.inputs.count == 1)
        #expect(transaction.outputs.contains { $0.value == recipientOutput.value && $0.lockingScript == recipientOutput.lockingScript })
        
        let changeOutputs = transaction.outputs.filter { $0.lockingScript == changeOutput.lockingScript }
        #expect(changeOutputs.count == 1)
        if let producedChange = changeOutputs.first {
            let expectedChangeAmount: UInt64 = 99_773
            #expect(producedChange.value == expectedChangeAmount)
        }
        
        let totalOutputs = transaction.outputs.reduce(into: UInt64(0)) { partialResult, output in
            partialResult += output.value
        }
        let expectedFee = utxo.value - totalOutputs
        #expect(transaction.calculateFee() == expectedFee)
        
        let transactionHex = transaction.encode().hexadecimalString
        let expectedTransactionHex = "02000000010102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20020000006b48304502200f79dc59b0f4926a4523fc7823dced7c3fe6b819af814f322919f843c6e04b5d022100cc9634550128ddc295ab07e466390a2f76699ffab5087aeb7b44f152310c4e214121034c571b087c1294a502870d5b3af90279365e8faed9dfce06b0d5b0e1177659b3ffffffff0250c30000000000001976a9144e22f7d2617323d696130dbe8ab44727042d15b588acbd850100000000001976a9144e7df7a4f7acfe23c6f593028a048a867a862b7f88ac00000000"
        #expect(transactionHex == expectedTransactionHex)
    }
}
