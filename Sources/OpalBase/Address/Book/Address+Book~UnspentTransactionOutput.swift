// Address+Book~UnspentTransactionOutput.swift

import Foundation

extension Address.Book {
    func addUnspentTransactionOutput(_ unspentTransactionOutput: Transaction.Output.Unspent) {
        unspentTransactionOutputStore.add(unspentTransactionOutput)
    }
    
    func addUnspentTransactionOutputs(_ unspentTransactionOutputs: [Transaction.Output.Unspent]) {
        unspentTransactionOutputStore.add(unspentTransactionOutputs)
    }
    
    func replaceUnspentTransactionOutputs(_ unspentTransactionOutputs: Set<Transaction.Output.Unspent>) {
        unspentTransactionOutputStore.replace(with: unspentTransactionOutputs)
    }
    
    func replaceUnspentTransactionOutputs(for address: Address, with unspentTransactionOutputs: [Transaction.Output.Unspent]) {
        unspentTransactionOutputStore.replace(for: address, with: unspentTransactionOutputs)
    }
    
    func removeUnspentTransactionOutput(_ unspentTransactionOutput: Transaction.Output.Unspent) {
        unspentTransactionOutputStore.remove(unspentTransactionOutput)
    }
    
    func removeUnspentTransactionOutputs(_ unspentTransactionOutputs: [Transaction.Output.Unspent]) {
        unspentTransactionOutputStore.remove(unspentTransactionOutputs)
    }
    
    func clearUnspentTransactionOutputs() {
        unspentTransactionOutputStore.clear()
    }
    
    func listUnspentTransactionOutputs() -> Set<Transaction.Output.Unspent> {
        unspentTransactionOutputStore.listUnspentTransactionOutputs()
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
    func selectUnspentTransactionOutputs(targetAmount: Satoshi,
                                         feePolicy: Wallet.FeePolicy,
                                         recommendationContext: Wallet.FeePolicy.RecommendationContext = .init(),
                                         override: Wallet.FeePolicy.Override? = nil,
                                         strategy: CoinSelection = .greedyLargestFirst) throws -> [Transaction.Output.Unspent] {
        let feePerByte = feePolicy.recommendedFeeRate(for: recommendationContext, override: override)
        switch strategy {
        case .greedyLargestFirst:
            var selectedUnspentTransactionOutputs: [Transaction.Output.Unspent] = .init()
            var totalAmount: UInt64 = 0
            let sortedUnspentTransactionOutputs = unspentTransactionOutputStore.sorted { $0.value > $1.value }
            
            let dustLimit = Transaction.dustLimit
            let recipientOutputs = CoinSelectionTemplates.recipientOutputs
            let outputsWithChange = CoinSelectionTemplates.outputsWithChange
            
            for unspentTransactionOutput in sortedUnspentTransactionOutputs {
                selectedUnspentTransactionOutputs.append(unspentTransactionOutput)
                totalAmount += unspentTransactionOutput.value
                
                if evaluateSelection(total: totalAmount,
                                     inputCount: selectedUnspentTransactionOutputs.count,
                                     targetAmount: targetAmount.uint64,
                                     recipientOutputs: recipientOutputs,
                                     outputsWithChange: outputsWithChange,
                                     dustLimit: dustLimit,
                                     feePerByte: feePerByte) != nil {
                    return selectedUnspentTransactionOutputs
                }
            }
            
            throw Error.insufficientFunds
        case .branchAndBound:
            let sortedUnspentTransactionOutputs = unspentTransactionOutputStore.sorted { $0.value > $1.value }
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
                
                guard index < sortedUnspentTransactionOutputs.count else { return }
                
                let remaining = sortedUnspentTransactionOutputs[index...].reduce(0) { $0 + $1.value }
                let estimatedFee = Transaction.estimateFee(inputCount: selection.count,
                                                           outputs: recipientOutputs,
                                                           feePerByte: feePerByte)
                let minimalRequirement = targetAmount.uint64 + estimatedFee
                if (total + remaining) < minimalRequirement { return }
                
                var nextSelection = selection
                nextSelection.append(sortedUnspentTransactionOutputs[index])
                exploreCombinations(index: index + 1, selection: nextSelection, total: total + sortedUnspentTransactionOutputs[index].value)
                exploreCombinations(index: index + 1, selection: selection, total: total)
            }
            
            exploreCombinations(index: 0, selection: .init(), total: 0)
            
            guard !bestSelection.isEmpty else { throw Error.insufficientFunds }
            return bestSelection
        case .sweepAll:
            return unspentTransactionOutputStore.sorted { $0.value > $1.value }
        }
    }
    
    func selectUnspentTransactionOutputs(targetAmount: Satoshi,
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
            for unspentTransactionOutput in unspentTransactionOutputStore.sorted(by: { $0.value > $1.value }) {
                selected.append(unspentTransactionOutput)
                total &+= unspentTransactionOutput.value
                
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
            let sorted = unspentTransactionOutputStore.sorted { $0.value > $1.value }
            var bestUnspentTransactionOutputs: [Transaction.Output.Unspent] = .init()
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
                        bestUnspentTransactionOutputs = selection
                    } else if evaluation.excess == currentBest.excess,
                              selection.count < bestUnspentTransactionOutputs.count {
                        bestEvaluation = evaluation
                        bestUnspentTransactionOutputs = selection
                    }
                } else {
                    bestEvaluation = evaluation
                    bestUnspentTransactionOutputs = selection
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
            guard !bestUnspentTransactionOutputs.isEmpty else { throw Error.insufficientFunds }
            return bestUnspentTransactionOutputs
            
        case .sweepAll:
            return unspentTransactionOutputStore.sorted { $0.value > $1.value }
        }
    }
}
