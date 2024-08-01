import Foundation
import SwiftFulcrum

extension Account {
    func calculateBalance() async throws -> Satoshi {
        var totalBalance: Satoshi = try Satoshi(0)
        let receivingAddresses = addressBook.getUsedReceivingAddresses()
        
        for address in receivingAddresses {
            let balance = try await address.fetchBalance()
            totalBalance = try totalBalance + balance
        }
        return totalBalance
    }
    
    func fetchUTXOs(for address: CashAddress) async throws -> [Transaction.Output.Unspent] {
        var utxos: [Transaction.Output.Unspent] = []
        
        let transactionHashes = try await address.fetchTransactionHistory()
        for transactionHash in transactionHashes {
            let transaction = try await Transaction.fetchTransactionDetails(for: transactionHash)
            for (index, output) in transaction.outputs.enumerated() {
                let decodedScript = try Script.decode(scriptPubKey: output.lockingScript)
                let decodedCashAddress = try CashAddress(decodedScript)
                let isOutputHasBeenSentToThisAddress = (decodedCashAddress == address)
                if isOutputHasBeenSentToThisAddress {
                    for input in transaction.inputs {
                        let isSomeInputReferTheReceivedOutput = (input.previousTransactionHash == transactionHash && input.previousTransactionOutputIndex == index)
                        let isOutputSpent = isSomeInputReferTheReceivedOutput
                        if !isOutputSpent {
                            let utxo = Transaction.Output.Unspent(transactionHash: transactionHash,
                                                                  outputIndex: .init(index),
                                                                  amount: output.value,
                                                                  lockingScript: output.lockingScript)
                            utxos.append(utxo)
                        }
                    }
                }
            }
        }
        
        return utxos
    }
    
    func send(_ value: Satoshi, from address: CashAddress, to recipient: CashAddress) async throws -> Bool {
        let transaction = try await createTransaction(from: address, to: recipient, value: value)
        
        return try await transaction.broadcast()
    }
}

