// Address+Book~UTXO.swift

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
}

extension Address.Book {
    func selectUTXOs(targetAmount: Satoshi,
                            feePerByte: UInt64 = 1,
                            strategy: CoinSelection = .greedyLargestFirst) throws -> [Transaction.Output.Unspent] {
        switch strategy {
        case .greedyLargestFirst:
            var selectedUTXOs: [Transaction.Output.Unspent] = []
            var totalAmount: UInt64 = 0
            let sortedUTXOs = utxos.sorted { $0.value > $1.value }
            
            for utxo in sortedUTXOs {
                selectedUTXOs.append(utxo)
                totalAmount += utxo.value
                
                let estimatedTransactionSize = (selectedUTXOs.count * 148) + 34 + 10
                let estimatedFee = UInt64(estimatedTransactionSize) * feePerByte
                
                if totalAmount >= targetAmount.uint64 + (estimatedFee * 2) {
                    return selectedUTXOs
                }
            }
            
            throw Error.insufficientFunds
        case .branchAndBound:
            let sortedUTXOs = utxos.sorted { $0.value > $1.value }
            var bestSelection: [Transaction.Output.Unspent] = .init()
            var bestExcess = UInt64.max
            
            func exploreCombinations(index: Int, selection: [Transaction.Output.Unspent], total: UInt64) {
                let estimatedTransactionSize = (selection.count * 148) + 34 + 10
                let estimatedFee = UInt64(estimatedTransactionSize) * feePerByte
                let target = targetAmount.uint64 + (estimatedFee * 2)
                
                if total >= target {
                    let excess = total - target
                    if excess < bestExcess {
                        bestExcess = excess
                        bestSelection = selection
                    }
                    return
                }
                
                guard index < sortedUTXOs.count else { return }
                
                let remaining = sortedUTXOs[index...].reduce(0) { $0 + $1.value }
                if (total + remaining) < target { return }
                
                var nextSelection = selection
                nextSelection.append(sortedUTXOs[index])
                exploreCombinations(index: index + 1, selection: nextSelection, total: total + sortedUTXOs[index].value)
                exploreCombinations(index: index + 1, selection: selection, total: total)
            }
            
            exploreCombinations(index: 0, selection: .init(), total: 0)
            
            guard !bestSelection.isEmpty else { throw Error.insufficientFunds }
            return bestSelection
        case .sweepAll:
            return utxos.sorted { $0.value > $1.value }
        }
    }
}
