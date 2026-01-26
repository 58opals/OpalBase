// Address+Book~UTXO.swift

import Foundation

extension Address.Book {
    func selectUTXOs(targetAmount: Satoshi,
                     feePolicy: Wallet.FeePolicy,
                     recommendationContext: Wallet.FeePolicy.RecommendationContext = .init(),
                     override: Wallet.FeePolicy.Override? = nil,
                     configuration: CoinSelection.Configuration = .makeTemplateConfiguration()) throws -> [Transaction.Output.Unspent] {
        let feePerByte = feePolicy.recommendFeeRate(for: recommendationContext, override: override)
        return try selectUTXOs(targetAmount: targetAmount,
                               feePerByte: feePerByte,
                               configuration: configuration)
    }
    
    private func selectUTXOs(targetAmount: Satoshi,
                             feePerByte: UInt64,
                             configuration: CoinSelection.Configuration) throws -> [Transaction.Output.Unspent] {
        let sortedUTXOs = sortSpendableBitcoinCashOnlyUnspentOutputs(by: { $0.value > $1.value } )
        let selector = CoinSelector(utxos: sortedUTXOs,
                                    configuration: configuration,
                                    targetAmount: targetAmount.uint64,
                                    feePerByte: feePerByte,
                                    dustLimit: Transaction.dustLimit)
        return try selector.select()
    }
    
    private func sortSpendableBitcoinCashOnlyUnspentOutputs(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool) -> [Transaction.Output.Unspent] {
        sortSpendableUTXOs(by: areInIncreasingOrder).filter { $0.tokenData == nil }
    }
}
