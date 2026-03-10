// OpalBase+Address+Book~TransactionHandling.swift

import Foundation

// MARK: - OpalBase.Transaction
extension _OpalBase.Address.Book {
    func handleIncomingTransaction(_ detailedTransaction: OpalBase.Transaction.Detail) async throws {
        for (index, output) in detailedTransaction.transaction.outputs.enumerated() {
            let lockingScript = output.lockingScript
            
            guard let script = try? OpalBase.Script.decode(lockingScript: lockingScript) else { continue }
            guard let address = try? OpalBase.Address(script: script) else { continue }
            guard inventory.contains(address: address) else { continue }
            
            try await mark(address: address, isUsed: true)
            let utxo = OpalBase.Transaction.Output.Unspent(output: output,
                                                  previousTransactionHash: detailedTransaction.hash,
                                                  previousTransactionOutputIndex: UInt32(index))
            addUTXO(utxo)
        }
    }
    
    func handleOutgoingTransaction(_ transaction: OpalBase.Transaction) {
        for input in transaction.inputs {
            if let utxo = utxoStore.findUTXO(matching: input) {
                removeUTXO(utxo)
            }
        }
    }
}

extension _OpalBase.Address.Book {
    func updateCacheValidityDuration(_ newDuration: TimeInterval) {
        inventory.updateCacheValidityDuration(to: newDuration)
    }
}
