// OpalBase+Address+Book+CoinSelectorModel.swift

import Foundation

extension _OpalBase.Address.Book {
    struct CoinSelectorModel {
        let utxos: [OpalBase.Transaction.OutputModel.UnspentModel]
        let configuration: OpalBase.Address.Book.CoinSelectionModel.Configuration
        let targetAmount: UInt64
        let feePerByte: UInt64
        let minimumRelayFeeRate: UInt64
        
        init(utxos: [OpalBase.Transaction.OutputModel.UnspentModel],
             configuration: OpalBase.Address.Book.CoinSelectionModel.Configuration,
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

extension _OpalBase.Address.Book.CoinSelectorModel {
    func select() throws -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        switch configuration.strategy {
        case .greedyLargestFirst:
            return try selectGreedy()
        case .branchAndBound:
            return try selectBranchAndBound()
        case .sweepAll:
            return utxos
        }
    }
    
    private func selectGreedy() throws -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        var selection: [OpalBase.Transaction.OutputModel.UnspentModel] = .init()
        var total: UInt64 = 0
        
        for utxo in utxos {
            selection.append(utxo)
            
            total = try total.addOrThrow(utxo.value,
                                         overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount)
            
            if try evaluate(selection: selection, sum: total) != nil {
                return selection
            }
        }
        
        throw OpalBase.Address.Book.Error.insufficientFunds
    }
    
    func evaluate(selection: [OpalBase.Transaction.OutputModel.UnspentModel],
                  sum: UInt64) throws -> OpalBase.Address.Book.CoinSelectionModel.EvaluationModel? {
        try OpalBase.Address.Book.CoinSelectionModel.evaluate(configuration: configuration,
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
                overflowError: OpalBase.Address.Book.Error.paymentExceedsMaximumAmount
            )
        }
        
        return suffixTotals
    }
}
