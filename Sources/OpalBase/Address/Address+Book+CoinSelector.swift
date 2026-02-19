// Address+Book+CoinSelector.swift

import Foundation

extension Address.Book {
    struct CoinSelector {
        let utxos: [Transaction.Output.Unspent]
        let configuration: Address.Book.CoinSelection.Configuration
        let targetAmount: UInt64
        let feePerByte: UInt64
        let minimumRelayFeeRate: UInt64
        
        init(utxos: [Transaction.Output.Unspent],
             configuration: Address.Book.CoinSelection.Configuration,
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

extension Address.Book.CoinSelector {
    func select() throws -> [Transaction.Output.Unspent] {
        switch configuration.strategy {
        case .greedyLargestFirst:
            return try selectGreedy()
        case .branchAndBound:
            return try selectBranchAndBound()
        case .sweepAll:
            return utxos
        }
    }
    
    private func selectGreedy() throws -> [Transaction.Output.Unspent] {
        var selection: [Transaction.Output.Unspent] = .init()
        var total: UInt64 = 0
        
        for utxo in utxos {
            selection.append(utxo)
            
            total = try total.addOrThrow(utxo.value,
                                         overflowError: Address.Book.Error.paymentExceedsMaximumAmount)
            
            if try evaluate(selection: selection, sum: total) != nil {
                return selection
            }
        }
        
        throw Address.Book.Error.insufficientFunds
    }
    
    func evaluate(selection: [Transaction.Output.Unspent],
                  sum: UInt64) throws -> Address.Book.CoinSelection.Evaluation? {
        try Address.Book.CoinSelection.evaluate(configuration: configuration,
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
                overflowError: Address.Book.Error.paymentExceedsMaximumAmount
            )
        }
        
        return suffixTotals
    }
}
