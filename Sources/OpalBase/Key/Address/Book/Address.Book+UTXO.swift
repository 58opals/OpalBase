import Foundation

extension Address.Book {
    func addUTXO(_ utxo: Transaction.Output.Unspent) {
        self.utxos.insert(utxo)
    }
    
    func addUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        self.utxos.formUnion(utxos)
    }
    
    func removeUTXO(_ utxo: Transaction.Output.Unspent) {
        self.utxos.remove(utxo)
    }
    
    func removeUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        self.utxos.subtract(utxos)
    }
    
    func clearUTXOs() {
        self.utxos.removeAll()
    }
    
    func getUTXOs() -> Set<Transaction.Output.Unspent> {
        return utxos
    }
    
    public func selectUTXOs(targetAmount: Satoshi,
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
}
