// Address+Book~UnspentTransactionOutput.swift

import Foundation

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
        return try selectUnspentTransactionOutputs(targetAmount: targetAmount,
                                                   feePerByte: feePerByte,
                                                   recipientOutputs: CoinSelectionTemplates.recipientOutputs,
                                                   outputsWithChange: CoinSelectionTemplates.outputsWithChange,
                                                   strategy: strategy)
    }
    
    func selectUnspentTransactionOutputs(targetAmount: Satoshi,
                                         feePolicy: Wallet.FeePolicy,
                                         recommendationContext: Wallet.FeePolicy.RecommendationContext = .init(),
                                         override: Wallet.FeePolicy.Override? = nil,
                                         recipientOutputs: [Transaction.Output],
                                         changeLockingScript: Data,
                                         strategy: CoinSelection = .greedyLargestFirst) throws -> [Transaction.Output.Unspent] {
        let changeTemplate = Transaction.Output(value: 0, lockingScript: changeLockingScript)
        let outputsWithChange = recipientOutputs + [changeTemplate]
        let feePerByte = feePolicy.recommendedFeeRate(for: recommendationContext, override: override)
        
        return try selectUnspentTransactionOutputs(targetAmount: targetAmount,
                                                   feePerByte: feePerByte,
                                                   recipientOutputs: recipientOutputs,
                                                   outputsWithChange: outputsWithChange,
                                                   strategy: strategy)
    }
    
    private func selectUnspentTransactionOutputs(targetAmount: Satoshi,
                                                 feePerByte: UInt64,
                                                 recipientOutputs: [Transaction.Output],
                                                 outputsWithChange: [Transaction.Output],
                                                 strategy: CoinSelection) throws -> [Transaction.Output.Unspent] {
        let sortedUnspentTransactionOutputs = unspentTransactionOutputStore.sorted { $0.value > $1.value }
        let dustLimit = Transaction.dustLimit
        
        switch strategy {
        case .greedyLargestFirst:
            var selectedUnspentTransactionOutputs: [Transaction.Output.Unspent] = .init()
            var totalAmount: UInt64 = 0
            
            for unspentTransactionOutput in sortedUnspentTransactionOutputs {
                selectedUnspentTransactionOutputs.append(unspentTransactionOutput)
                totalAmount &+= unspentTransactionOutput.value
                
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
            var bestSelection: [Transaction.Output.Unspent] = .init()
            var bestEvaluation: CoinSelectionEvaluation?
            
            var suffixTotals: [UInt64] = Array(repeating: 0, count: sortedUnspentTransactionOutputs.count + 1)
            if !sortedUnspentTransactionOutputs.isEmpty {
                for index in stride(from: sortedUnspentTransactionOutputs.count - 1, through: 0, by: -1) {
                    suffixTotals[index] = suffixTotals[index + 1] &+ sortedUnspentTransactionOutputs[index].value
                }
            }
            
            func updateBest(selection: [Transaction.Output.Unspent], sum: UInt64) {
                guard let evaluation = evaluateSelection(total: sum,
                                                         inputCount: selection.count,
                                                         targetAmount: targetAmount.uint64,
                                                         recipientOutputs: recipientOutputs,
                                                         outputsWithChange: outputsWithChange,
                                                         dustLimit: dustLimit,
                                                         feePerByte: feePerByte) else { return }
                
                if let currentBest = bestEvaluation {
                    if evaluation.excess < currentBest.excess {
                        bestEvaluation = evaluation
                        bestSelection = selection
                    } else if evaluation.excess == currentBest.excess,
                              selection.count < bestSelection.count {
                        bestEvaluation = evaluation
                        bestSelection = selection
                    }
                } else {
                    bestEvaluation = evaluation
                    bestSelection = selection
                }
                
            }
            
            func explore(index: Int, selection: [Transaction.Output.Unspent], sum: UInt64) {
                updateBest(selection: selection, sum: sum)
                
                guard index < sortedUnspentTransactionOutputs.count else { return }
                
                let remaining = suffixTotals[index]
                let minimalFee = Transaction.estimateFee(inputCount: selection.count,
                                                         outputs: recipientOutputs,
                                                         feePerByte: feePerByte)
                let minimalRequirement = targetAmount.uint64 &+ minimalFee
                if sum &+ remaining < minimalRequirement { return }
                
                var selectionIncludingCurrent = selection
                selectionIncludingCurrent.append(sortedUnspentTransactionOutputs[index])
                let sumIncludingCurrent = sum &+ sortedUnspentTransactionOutputs[index].value
                
                explore(index: index + 1,
                        selection: selectionIncludingCurrent,
                        sum: sumIncludingCurrent)
                explore(index: index + 1, selection: selection, sum: sum)
            }
            
            explore(index: 0, selection: .init(), sum: 0)
            guard !bestSelection.isEmpty else { throw Error.insufficientFunds }
            return bestSelection
            
        case .sweepAll:
            return sortedUnspentTransactionOutputs
        }
    }
}
