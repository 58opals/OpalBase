// OpalBase+Address+Book+CoinSelector~BranchAndBound.swift

import Foundation

extension _OpalBase.Address.Book.CoinSelector {
    func selectBranchAndBound() throws -> [OpalBase.Transaction.Output.Unspent] {
        var bestSelection: [OpalBase.Transaction.Output.Unspent] = .init()
        var bestEvaluation: OpalBase.Address.Book.CoinSelection.Evaluation?
        let suffixTotals = try makeSuffixTotals()
        
        func updateBest(selection: [OpalBase.Transaction.Output.Unspent], sum: UInt64) throws {
            guard let evaluation = try evaluate(selection: selection, sum: sum) else { return }
            
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
        
        func explore(index: Int, selection: [OpalBase.Transaction.Output.Unspent], sum: UInt64) throws {
            try updateBest(selection: selection, sum: sum)
            
            guard index < utxos.count else { return }
            
            let remaining = suffixTotals[index]
            let minimalFee = try OpalBase.Transaction.estimateFee(inputCount: selection.count,
                                                         outputs: configuration.recipientOutputs,
                                                         feePerByte: feePerByte)
            let minimalRequirement = try targetAmount.addOrThrow(
                minimalFee,
                overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
            )
            let sumWithRemaining = try sum.addOrThrow(remaining,
                                                      overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount)
            if sumWithRemaining < minimalRequirement { return }
            var selectionIncludingCurrent = selection
            selectionIncludingCurrent.append(utxos[index])
            let sumIncludingCurrent = try sum.addOrThrow(
                utxos[index].value,
                overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
            )
            
            try explore(index: index + 1,
                        selection: selectionIncludingCurrent,
                        sum: sumIncludingCurrent)
            try explore(index: index + 1, selection: selection, sum: sum)
        }
        
        try explore(index: 0, selection: .init(), sum: 0)
        guard !bestSelection.isEmpty else { throw OpalBase.Address.Book.Error.insufficientFunds }
        return bestSelection
    }
}
