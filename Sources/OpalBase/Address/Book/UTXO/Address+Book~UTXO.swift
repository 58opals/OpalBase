// Address+Book~UTXO.swift

import Foundation

extension Address.Book {
    func selectUTXOs(targetAmount: Satoshi,
                     feePolicy: Wallet.FeePolicy,
                     recommendationContext: Wallet.FeePolicy.RecommendationContext = .init(),
                     override: Wallet.FeePolicy.Override? = nil,
                     configuration: CoinSelection.Configuration = .makeTemplateConfiguration()) throws -> [Transaction.Output.Unspent] {
        let feePerByte = feePolicy.recommendedFeeRate(for: recommendationContext, override: override)
        return try selectUTXOs(targetAmount: targetAmount,
                               feePerByte: feePerByte,
                               configuration: configuration)
    }
    
    private func selectUTXOs(targetAmount: Satoshi,
                             feePerByte: UInt64,
                             configuration: CoinSelection.Configuration) throws -> [Transaction.Output.Unspent] {
        let sortedUTXOs = sortedUTXOs(by: { $0.value > $1.value })
        let dustLimit = Transaction.dustLimit
        
        switch configuration.strategy {
        case .greedyLargestFirst:
            var selectedUTXOs: [Transaction.Output.Unspent] = .init()
            var totalAmount: UInt64 = 0
            
            for utxo in sortedUTXOs {
                selectedUTXOs.append(utxo)
                totalAmount &+= utxo.value
                
                if CoinSelection.evaluate(total: totalAmount,
                                          inputCount: selectedUTXOs.count,
                                          targetAmount: targetAmount.uint64,
                                          recipientOutputs: configuration.recipientOutputs,
                                          outputsWithChange: configuration.outputsWithChange,
                                          dustLimit: dustLimit,
                                          feePerByte: feePerByte) != nil {
                    return selectedUTXOs
                }
            }
            
            throw Error.insufficientFunds
            
        case .branchAndBound:
            var bestSelection: [Transaction.Output.Unspent] = .init()
            var bestEvaluation: CoinSelection.Evaluation?
            
            var suffixTotals: [UInt64] = Array(repeating: 0, count: sortedUTXOs.count + 1)
            if !sortedUTXOs.isEmpty {
                for index in stride(from: sortedUTXOs.count - 1, through: 0, by: -1) {
                    suffixTotals[index] = suffixTotals[index + 1] &+ sortedUTXOs[index].value
                }
            }
            
            func updateBest(selection: [Transaction.Output.Unspent], sum: UInt64) {
                guard let evaluation = CoinSelection.evaluate(total: sum,
                                                              inputCount: selection.count,
                                                              targetAmount: targetAmount.uint64,
                                                              recipientOutputs: configuration.recipientOutputs,
                                                              outputsWithChange: configuration.outputsWithChange,
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
                
                guard index < sortedUTXOs.count else { return }
                
                let remaining = suffixTotals[index]
                let minimalFee = Transaction.estimateFee(inputCount: selection.count,
                                                         outputs: configuration.recipientOutputs,
                                                         feePerByte: feePerByte)
                let minimalRequirement = targetAmount.uint64 &+ minimalFee
                if sum &+ remaining < minimalRequirement { return }
                
                var selectionIncludingCurrent = selection
                selectionIncludingCurrent.append(sortedUTXOs[index])
                let sumIncludingCurrent = sum &+ sortedUTXOs[index].value
                
                explore(index: index + 1,
                        selection: selectionIncludingCurrent,
                        sum: sumIncludingCurrent)
                explore(index: index + 1, selection: selection, sum: sum)
            }
            
            explore(index: 0, selection: .init(), sum: 0)
            guard !bestSelection.isEmpty else { throw Error.insufficientFunds }
            return bestSelection
            
        case .sweepAll:
            return sortedUTXOs
        }
    }
}
