import Foundation

extension Address.Book {
    mutating func addUTXO(_ utxo: Transaction.Output.Unspent) {
        self.utxos.insert(utxo)
    }
    
    mutating func addUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        self.utxos.formUnion(utxos)
    }
    
    mutating func removeUTXO(_ utxo: Transaction.Output.Unspent) {
        self.utxos.remove(utxo)
    }
    
    mutating func removeUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        self.utxos.subtract(utxos)
    }
    
    mutating func clearUTXOs() {
        self.utxos.removeAll()
    }
    
    func getUTXOs() -> Set<Transaction.Output.Unspent> {
        return utxos
    }
    
    func selectUTXOs(targetAmount: Satoshi,
                     feePerByte: UInt64 = 1) throws -> [Transaction.Output.Unspent] {
        var selectedUTXOs: [Transaction.Output.Unspent] = []
        var totalAmount: UInt64 = 0
        let sortedUTXOs = utxos.sorted { $0.value > $1.value }
        
        for utxo in sortedUTXOs {
            selectedUTXOs.append(utxo)
            totalAmount += utxo.value
            
            let estimatedTransactionSize = selectedUTXOs.count * 148 + 34 + 10
            let estimatedFee = UInt64(estimatedTransactionSize) * feePerByte
            
            if totalAmount >= targetAmount.uint64 + (estimatedFee*2) {
                return selectedUTXOs
            }
        }
        
        throw Error.insufficientFunds
    }
    
    mutating func refreshUTXOSet() async throws {
        var updatedUTXOs = [Transaction.Output.Unspent]()
        
        for entry in (receivingEntries + changeEntries) {
            let newUTXOs = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
            let newUTXOsWithTheCorrectlyOrderedPreviousTransactionHash = newUTXOs.map {
                Transaction.Output.Unspent(value: $0.value,
                                           lockingScript: $0.lockingScript,
                                           previousTransactionHash: $0.previousTransactionHash,
                                           previousTransactionOutputIndex: $0.previousTransactionOutputIndex)
            }
            updatedUTXOs.append(contentsOf: newUTXOsWithTheCorrectlyOrderedPreviousTransactionHash)
        }
        
        clearUTXOs()
        addUTXOs(updatedUTXOs)
    }
}
