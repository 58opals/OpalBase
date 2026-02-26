// AddressModel+BookActor+CoinSelectorModel~BranchAndBound.swift

import Foundation

extension AddressModel.BookActor.CoinSelectorModel {
    func selectBranchAndBound() throws -> [TransactionModel.OutputModel.UnspentModel] {
        var bestSelection: [TransactionModel.OutputModel.UnspentModel] = .init()
        var bestEvaluation: AddressModel.BookActor.CoinSelectionModel.EvaluationModel?
        let suffixTotals = try makeSuffixTotals()
        
        func updateBest(selection: [TransactionModel.OutputModel.UnspentModel], sum: UInt64) throws {
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
        
        func explore(index: Int, selection: [TransactionModel.OutputModel.UnspentModel], sum: UInt64) throws {
            try updateBest(selection: selection, sum: sum)
            
            guard index < utxos.count else { return }
            
            let remaining = suffixTotals[index]
            let minimalFee = try TransactionModel.estimateFee(inputCount: selection.count,
                                                         outputs: configuration.recipientOutputs,
                                                         feePerByte: feePerByte)
            let minimalRequirement = try targetAmount.addOrThrow(
                minimalFee,
                overflowError: AddressModel.BookActor.Error.paymentExceedsMaximumAmount
            )
            let sumWithRemaining = try sum.addOrThrow(remaining,
                                                      overflowError: AddressModel.BookActor.Error.paymentExceedsMaximumAmount)
            if sumWithRemaining < minimalRequirement { return }
            var selectionIncludingCurrent = selection
            selectionIncludingCurrent.append(utxos[index])
            let sumIncludingCurrent = try sum.addOrThrow(
                utxos[index].value,
                overflowError: AddressModel.BookActor.Error.paymentExceedsMaximumAmount
            )
            
            try explore(index: index + 1,
                        selection: selectionIncludingCurrent,
                        sum: sumIncludingCurrent)
            try explore(index: index + 1, selection: selection, sum: sum)
        }
        
        try explore(index: 0, selection: .init(), sum: 0)
        guard !bestSelection.isEmpty else { throw AddressModel.BookActor.Error.insufficientFunds }
        return bestSelection
    }
}
