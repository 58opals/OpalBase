// Address+Book~TransactionHandling.swift

import Foundation

// MARK: - Transaction
extension Address.Book {
    func handleIncomingTransaction(_ detailedTransaction: Transaction.Detailed) async throws {
        for (index, output) in detailedTransaction.transaction.outputs.enumerated() {
            let lockingScript = output.lockingScript
            
            guard let script = try? Script.decode(lockingScript: lockingScript) else { continue }
            guard let address = try? Address(script: script) else { continue }
            guard inventory.contains(address: address) else { continue }
            
            try await mark(address: address, isUsed: true)
            let utxo = Transaction.Output.Unspent(output: output,
                                                  previousTransactionHash: detailedTransaction.hash,
                                                  previousTransactionOutputIndex: UInt32(index))
            addUTXO(utxo)
        }
    }
    
    func handleOutgoingTransaction(_ transaction: Transaction) {
        for input in transaction.inputs {
            if let utxo = utxoStore.findUTXO(matching: input) {
                removeUTXO(utxo)
            }
        }
    }
}

extension Address.Book {
    func updateCacheValidityDuration(_ newDuration: TimeInterval) {
        inventory.updateCacheValidityDuration(to: newDuration)
    }
}
