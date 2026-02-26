// AddressModel+BookActor~TransactionHandling.swift

import Foundation

// MARK: - TransactionModel
extension AddressModel.BookActor {
    func handleIncomingTransaction(_ detailedTransaction: TransactionModel.DetailedModel) async throws {
        for (index, output) in detailedTransaction.transaction.outputs.enumerated() {
            let lockingScript = output.lockingScript
            
            guard let script = try? ScriptModel.decode(lockingScript: lockingScript) else { continue }
            guard let address = try? AddressModel(script: script) else { continue }
            guard inventory.contains(address: address) else { continue }
            
            try await mark(address: address, isUsed: true)
            let utxo = TransactionModel.OutputModel.UnspentModel(output: output,
                                                  previousTransactionHash: detailedTransaction.hash,
                                                  previousTransactionOutputIndex: UInt32(index))
            addUTXO(utxo)
        }
    }
    
    func handleOutgoingTransaction(_ transaction: TransactionModel) {
        for input in transaction.inputs {
            if let utxo = utxoStore.findUTXO(matching: input) {
                removeUTXO(utxo)
            }
        }
    }
}

extension AddressModel.BookActor {
    func updateCacheValidityDuration(_ newDuration: TimeInterval) {
        inventory.updateCacheValidityDuration(to: newDuration)
    }
}
