import Foundation
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("Transaction Fulcrum Funding", .tags(.integration, .network, .fulcrum, .transaction, .crypto, .key))
struct TransactionFulcrumFundingSuite {
    @Test("builds signed transaction from live UTXOs", .tags(.integration, .network, .fulcrum, .transaction, .crypto, .key))
    func buildsSignedTransactionFromLiveUTXOs() async throws {
        guard
            Environment.network,
            let endpoint = Environment.fulcrumURL,
            let wif = Environment.walletWIF,
            let recipientString = Environment.transactionRecipient,
            let satoshis = Environment.transactionSatoshis,
            let feeRate = Environment.transactionFeePerByte
        else { return }
        
        let privateKey = try PrivateKey(wif: wif)
        let publicKey = try PublicKey(privateKey: privateKey)
        let sourceAddress = try Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
        let recipientAddress = try Address(recipientString)
        
        let fulcrum = try await Fulcrum(url: endpoint)
        let utxos = try await sourceAddress.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
        
        #expect(!utxos.isEmpty, "The funded WIF must provide spendable UTXOs for the integration test.")
        
        let utxoPrivateKeyPairs = Dictionary(uniqueKeysWithValues: utxos.map { ($0, privateKey) })
        let totalValue = utxos.reduce(into: UInt64(0)) { $0 += $1.value }
        
        #expect(totalValue > satoshis, "The funded balance must exceed the requested send amount to preserve change.")
        
        let changeCandidate = totalValue - satoshis
        let recipientOutput = Transaction.Output(value: satoshis, address: recipientAddress)
        let changeOutput = Transaction.Output(value: changeCandidate, address: sourceAddress)
        
        let transaction = try Transaction.build(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                                                recipientOutputs: [recipientOutput],
                                                changeOutput: changeOutput,
                                                feePerByte: feeRate)
        
        let outputs = transaction.outputs
        let recipientMatch = outputs.first { $0.lockingScript == recipientOutput.lockingScript }
        #expect(recipientMatch != nil, "The built transaction must include the requested recipient output.")
        #expect(recipientMatch?.value == satoshis)
        
        let changeMatch = outputs.first { $0.lockingScript == changeOutput.lockingScript }
        #expect(changeMatch != nil, "The built transaction must return change to the source address.")
        if let changeMatch {
            #expect(changeMatch.value > 0, "The change output should hold a positive value after fees are applied.")
        }
        
        let encodedTransaction = transaction.encode()
        let (decoded, _) = try Transaction.decode(from: encodedTransaction)
        
        struct InputReference: Hashable {
            let hash: Transaction.Hash
            let index: UInt32
        }
        
        let decodedReferences = Set(decoded.inputs.map { InputReference(hash: $0.previousTransactionHash,
                                                                        index: $0.previousTransactionOutputIndex) })
        let expectedReferences = Set(utxos.map { InputReference(hash: $0.previousTransactionHash,
                                                                index: $0.previousTransactionOutputIndex) })
        
        #expect(decodedReferences == expectedReferences, "The signed transaction must reference the fetched UTXOs.")
        
        Issue.record("Raw transaction hex: \(encodedTransaction.hexadecimalString)")
    }
}
