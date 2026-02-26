// AddressModel+BookActor+CoinSelectorModel.swift

import Foundation

extension AddressModel.BookActor {
    struct CoinSelectorModel {
        let utxos: [TransactionModel.OutputModel.UnspentModel]
        let configuration: AddressModel.BookActor.CoinSelectionModel.Configuration
        let targetAmount: UInt64
        let feePerByte: UInt64
        let minimumRelayFeeRate: UInt64
        
        init(utxos: [TransactionModel.OutputModel.UnspentModel],
             configuration: AddressModel.BookActor.CoinSelectionModel.Configuration,
             targetAmount: UInt64,
             feePerByte: UInt64,
             minimumRelayFeeRate: UInt64) {
            self.utxos = utxos
            self.configuration = configuration
            self.targetAmount = targetAmount
            self.feePerByte = feePerByte
            self.minimumRelayFeeRate = minimumRelayFeeRate
        }
    }
}

extension AddressModel.BookActor.CoinSelectorModel {
    func select() throws -> [TransactionModel.OutputModel.UnspentModel] {
        switch configuration.strategy {
        case .greedyLargestFirst:
            return try selectGreedy()
        case .branchAndBound:
            return try selectBranchAndBound()
        case .sweepAll:
            return utxos
        }
    }
    
    private func selectGreedy() throws -> [TransactionModel.OutputModel.UnspentModel] {
        var selection: [TransactionModel.OutputModel.UnspentModel] = .init()
        var total: UInt64 = 0
        
        for utxo in utxos {
            selection.append(utxo)
            
            total = try total.addOrThrow(utxo.value,
                                         overflowError: AddressModel.BookActor.Error.paymentExceedsMaximumAmount)
            
            if try evaluate(selection: selection, sum: total) != nil {
                return selection
            }
        }
        
        throw AddressModel.BookActor.Error.insufficientFunds
    }
    
    func evaluate(selection: [TransactionModel.OutputModel.UnspentModel],
                  sum: UInt64) throws -> AddressModel.BookActor.CoinSelectionModel.EvaluationModel? {
        try AddressModel.BookActor.CoinSelectionModel.evaluate(configuration: configuration,
                                                total: sum,
                                                inputCount: selection.count,
                                                targetAmount: targetAmount,
                                                recipientOutputs: configuration.recipientOutputs,
                                                outputsWithChange: configuration.outputsWithChange,
                                                minimumRelayFeeRate: minimumRelayFeeRate,
                                                feePerByte: feePerByte)
    }
    
    func makeSuffixTotals() throws -> [UInt64] {
        guard !utxos.isEmpty else { return [0] }
        
        var suffixTotals: [UInt64] = Array(repeating: 0, count: utxos.count + 1)
        for index in stride(from: utxos.count - 1, through: 0, by: -1) {
            suffixTotals[index] = try suffixTotals[index + 1].addOrThrow(
                utxos[index].value,
                overflowError: AddressModel.BookActor.Error.paymentExceedsMaximumAmount
            )
        }
        
        return suffixTotals
    }
}
