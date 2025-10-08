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
    
    func listUTXOs() -> Set<Transaction.Output.Unspent> {
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
                
                if totalAmount >= targetAmount.uint64 + (estimatedFee) {
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
                let target = targetAmount.uint64 + (estimatedFee)
                
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
    
    func selectUTXOs(targetAmount: Satoshi,
                     recipientOutputs: [Transaction.Output],
                     changeLockingScript: Data,
                     feePerByte: UInt64 = 1,
                     strategy: CoinSelection = .greedyLargestFirst) throws -> [Transaction.Output.Unspent] {
        let dust = Transaction.dustLimit
        let changeTemplate = Transaction.Output(value: 0, lockingScript: changeLockingScript)
        let withChangeOutputs = recipientOutputs + [changeTemplate]
        
        switch strategy {
        case .greedyLargestFirst:
            var selected: [Transaction.Output.Unspent] = []
            var total: UInt64 = 0
            for utxo in utxos.sorted(by: { $0.value > $1.value }) {
                selected.append(utxo)
                total &+= utxo.value
                
                let feeWithChange = Transaction.estimatedFee(inputCount: selected.count,
                                                             outputs: withChangeOutputs,
                                                             feePerByte: feePerByte)
                if total >= targetAmount.uint64 &+ feeWithChange {
                    let change = total &- targetAmount.uint64 &- feeWithChange
                    if change == 0 || change >= dust { return selected }
                }
            }
            throw Error.insufficientFunds
            
        case .branchAndBound:
            let sorted = utxos.sorted { $0.value > $1.value }
            var bestUTXOs: [Transaction.Output.Unspent] = []
            var bestChange: UInt64?
            
            func explore(index: Int, selection: [Transaction.Output.Unspent], sum: UInt64) {
                if index >= sorted.count { return }
                
                var remaining: UInt64 = 0
                for index in index..<sorted.count { remaining &+= sorted[index].value }
                let minimumFee = Transaction.estimatedFee(inputCount: selection.count,
                                                          outputs: withChangeOutputs,
                                                          feePerByte: feePerByte)
                if sum &+ remaining < targetAmount.uint64 &+ minimumFee { return }
                
                var selectionIncluded = selection; selectionIncluded.append(sorted[index])
                let sumIncluded = sum &+ sorted[index].value
                let feeIncluded = Transaction.estimatedFee(inputCount: selectionIncluded.count,
                                                           outputs: withChangeOutputs,
                                                           feePerByte: feePerByte)
                if sumIncluded >= targetAmount.uint64 &+ feeIncluded {
                    let change = sumIncluded &- targetAmount.uint64 &- feeIncluded
                    if change == 0 || change >= dust {
                        if let best = bestChange {
                            if change < best { bestChange = change; bestUTXOs = selectionIncluded }
                        } else {
                            bestChange = change; bestUTXOs = selectionIncluded
                        }
                    }
                } else {
                    explore(index: index + 1, selection: selectionIncluded, sum: sumIncluded)
                }
                
                explore(index: index + 1, selection: selection, sum: sum)
            }
            
            explore(index: 0, selection: [], sum: 0)
            guard !bestUTXOs.isEmpty else { throw Error.insufficientFunds }
            return bestUTXOs
            
        case .sweepAll:
            return utxos.sorted { $0.value > $1.value }
        }
    }
}
