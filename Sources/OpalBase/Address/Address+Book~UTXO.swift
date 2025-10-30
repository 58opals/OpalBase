// Address+Book~UTXO.swift

import Foundation

extension Address.Book {
    func addUTXO(_ utxo: Transaction.Output.Unspent) {
        self.utxos.insert(utxo)
    }
    
    func addUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        self.utxos.formUnion(utxos)
    }
    
    func replaceUTXOs(_ utxos: Set<Transaction.Output.Unspent>) {
        self.utxos = utxos
    }
    
    func replaceUTXOs(for address: Address, with utxos: [Transaction.Output.Unspent]) {
        let lockingScript = address.lockingScript.data
        let existingMatches = self.utxos.filter { $0.lockingScript == lockingScript }
        if !existingMatches.isEmpty {
            self.utxos.subtract(existingMatches)
        }
        if !utxos.isEmpty {
            self.utxos.formUnion(utxos)
        }
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
    private struct CoinSelectionEvaluation {
        let excess: UInt64
    }
    
    private enum CoinSelectionTemplates {
        static var lockingScript: Data { Data(repeating: 0, count: 25) }
        
        static var recipientOutputs: [Transaction.Output] {
            [Transaction.Output(value: 0, lockingScript: lockingScript)]
        }
        
        static var outputsWithChange: [Transaction.Output] {
            let recipient = Transaction.Output(value: 0, lockingScript: lockingScript)
            let change = Transaction.Output(value: 0, lockingScript: lockingScript)
            return [recipient, change]
        }
    }
    
    private func evaluateSelection(total: UInt64,
                                   inputCount: Int,
                                   targetAmount: UInt64,
                                   recipientOutputs: [Transaction.Output],
                                   outputsWithChange: [Transaction.Output],
                                   dustLimit: UInt64,
                                   feePerByte: UInt64) -> CoinSelectionEvaluation? {
        let feeWithoutChange = Transaction.estimateFee(inputCount: inputCount,
                                                       outputs: recipientOutputs,
                                                       feePerByte: feePerByte)
        let requiredWithoutChange = targetAmount &+ feeWithoutChange
        
        if total >= requiredWithoutChange {
            let excess = total &- requiredWithoutChange
            if excess == 0 || excess < dustLimit {
                return CoinSelectionEvaluation(excess: excess)
            }
        }
        
        let feeWithChange = Transaction.estimateFee(inputCount: inputCount,
                                                    outputs: outputsWithChange,
                                                    feePerByte: feePerByte)
        let requiredWithChange = targetAmount &+ feeWithChange
        
        guard total >= requiredWithChange else { return nil }
        
        let change = total &- requiredWithChange
        guard change == 0 || change >= dustLimit else { return nil }
        
        return CoinSelectionEvaluation(excess: change)
    }
}

extension Address.Book {
    func selectUTXOs(targetAmount: Satoshi,
                     feePolicy: Wallet.FeePolicy,
                     recommendationContext: Wallet.FeePolicy.RecommendationContext = .init(),
                     override: Wallet.FeePolicy.Override? = nil,
                     strategy: CoinSelection = .greedyLargestFirst) throws -> [Transaction.Output.Unspent] {
        let feePerByte = feePolicy.recommendedFeeRate(for: recommendationContext, override: override)
        switch strategy {
        case .greedyLargestFirst:
            var selectedUTXOs: [Transaction.Output.Unspent] = .init()
            var totalAmount: UInt64 = 0
            let sortedUTXOs = utxos.sorted { $0.value > $1.value }
            
            let dustLimit = Transaction.dustLimit
            let recipientOutputs = CoinSelectionTemplates.recipientOutputs
            let outputsWithChange = CoinSelectionTemplates.outputsWithChange
            
            for utxo in sortedUTXOs {
                selectedUTXOs.append(utxo)
                totalAmount += utxo.value
                
                if evaluateSelection(total: totalAmount,
                                     inputCount: selectedUTXOs.count,
                                     targetAmount: targetAmount.uint64,
                                     recipientOutputs: recipientOutputs,
                                     outputsWithChange: outputsWithChange,
                                     dustLimit: dustLimit,
                                     feePerByte: feePerByte) != nil {
                    return selectedUTXOs
                }
            }
            
            throw Error.insufficientFunds
        case .branchAndBound:
            let sortedUTXOs = utxos.sorted { $0.value > $1.value }
            var bestSelection: [Transaction.Output.Unspent] = .init()
            var bestExcess = UInt64.max
            
            let dustLimit = Transaction.dustLimit
            let recipientOutputs = CoinSelectionTemplates.recipientOutputs
            let outputsWithChange = CoinSelectionTemplates.outputsWithChange
            
            func exploreCombinations(index: Int, selection: [Transaction.Output.Unspent], total: UInt64) {
                if let evaluation = evaluateSelection(total: total,
                                                      inputCount: selection.count,
                                                      targetAmount: targetAmount.uint64,
                                                      recipientOutputs: recipientOutputs,
                                                      outputsWithChange: outputsWithChange,
                                                      dustLimit: dustLimit,
                                                      feePerByte: feePerByte) {
                    let excess = evaluation.excess
                    if excess < bestExcess {
                        bestExcess = excess
                        bestSelection = selection
                    }
                    return
                }
                
                guard index < sortedUTXOs.count else { return }
                
                let remaining = sortedUTXOs[index...].reduce(0) { $0 + $1.value }
                let estimatedFee = Transaction.estimateFee(inputCount: selection.count,
                                                           outputs: recipientOutputs,
                                                           feePerByte: feePerByte)
                let minimalRequirement = targetAmount.uint64 + estimatedFee
                if (total + remaining) < minimalRequirement { return }
                
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
                     feePolicy: Wallet.FeePolicy,
                     recommendationContext: Wallet.FeePolicy.RecommendationContext = .init(),
                     override: Wallet.FeePolicy.Override? = nil,
                     recipientOutputs: [Transaction.Output],
                     changeLockingScript: Data,
                     strategy: CoinSelection = .greedyLargestFirst) throws -> [Transaction.Output.Unspent] {
        let dust = Transaction.dustLimit
        let changeTemplate = Transaction.Output(value: 0, lockingScript: changeLockingScript)
        let withChangeOutputs = recipientOutputs + [changeTemplate]
        let feePerByte = feePolicy.recommendedFeeRate(for: recommendationContext, override: override)
        
        switch strategy {
        case .greedyLargestFirst:
            var selected: [Transaction.Output.Unspent] = .init()
            var total: UInt64 = 0
            for utxo in utxos.sorted(by: { $0.value > $1.value }) {
                selected.append(utxo)
                total &+= utxo.value
                
                if evaluateSelection(total: total,
                                     inputCount: selected.count,
                                     targetAmount: targetAmount.uint64,
                                     recipientOutputs: recipientOutputs,
                                     outputsWithChange: withChangeOutputs,
                                     dustLimit: dust,
                                     feePerByte: feePerByte) != nil {
                    return selected
                }
            }
            throw Error.insufficientFunds
            
        case .branchAndBound:
            let sorted = utxos.sorted { $0.value > $1.value }
            var bestUTXOs: [Transaction.Output.Unspent] = .init()
            var bestEvaluation: CoinSelectionEvaluation?
            
            let dust = Transaction.dustLimit
            
            var suffixTotals: [UInt64] = Array(repeating: 0, count: sorted.count + 1)
            if !sorted.isEmpty {
                for index in stride(from: sorted.count - 1, through: 0, by: -1) {
                    suffixTotals[index] = suffixTotals[index + 1] &+ sorted[index].value
                }
            }
            
            func updateBest(selection: [Transaction.Output.Unspent], sum: UInt64) {
                guard let evaluation = evaluateSelection(total: sum,
                                                         inputCount: selection.count,
                                                         targetAmount: targetAmount.uint64,
                                                         recipientOutputs: recipientOutputs,
                                                         outputsWithChange: withChangeOutputs,
                                                         dustLimit: dust,
                                                         feePerByte: feePerByte) else { return }
                
                if let currentBest = bestEvaluation {
                    if evaluation.excess < currentBest.excess {
                        bestEvaluation = evaluation
                        bestUTXOs = selection
                    } else if evaluation.excess == currentBest.excess,
                              selection.count < bestUTXOs.count {
                        bestEvaluation = evaluation
                        bestUTXOs = selection
                    }
                } else {
                    bestEvaluation = evaluation
                    bestUTXOs = selection
                }
                
            }
            
            func explore(index: Int, selection: [Transaction.Output.Unspent], sum: UInt64) {
                updateBest(selection: selection, sum: sum)
                
                guard index < sorted.count else { return }
                
                let remaining = suffixTotals[index]
                let minimalFee = Transaction.estimateFee(inputCount: selection.count,
                                                         outputs: recipientOutputs,
                                                         feePerByte: feePerByte)
                let minimalRequirement = targetAmount.uint64 &+ minimalFee
                if sum &+ remaining < minimalRequirement { return }
                
                var selectionIncluded = selection
                selectionIncluded.append(sorted[index])
                let sumIncluded = sum &+ sorted[index].value
                
                explore(index: index + 1, selection: selectionIncluded, sum: sumIncluded)
                explore(index: index + 1, selection: selection, sum: sum)
            }
            
            explore(index: 0, selection: .init(), sum: 0)
            guard !bestUTXOs.isEmpty else { throw Error.insufficientFunds }
            return bestUTXOs
            
        case .sweepAll:
            return utxos.sorted { $0.value > $1.value }
        }
    }
}
