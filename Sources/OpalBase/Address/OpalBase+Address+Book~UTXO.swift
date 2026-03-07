// OpalBase+Address+Book~UTXO.swift

import Foundation

extension _OpalBase.Address.Book {
    func selectUTXOs(targetAmount: OpalBase.Satoshi,
                     feePolicy: OpalBase.Wallet.FeePolicy,
                     recommendationContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
                     override: OpalBase.Wallet.FeePolicy.Override? = nil,
                     configuration: CoinSelectionModel.Configuration = .makeTemplateConfiguration()) throws -> [OpalBase.Transaction.OutputModel.Unspent] {
        let feePerByte = feePolicy.recommendFeeRate(for: recommendationContext, override: override)
        return try selectUTXOs(targetAmount: targetAmount,
                               feePerByte: feePerByte,
                               configuration: configuration)
    }
    
    private func selectUTXOs(targetAmount: OpalBase.Satoshi,
                             feePerByte: UInt64,
                             configuration: CoinSelectionModel.Configuration) throws -> [OpalBase.Transaction.OutputModel.Unspent] {
        let sortedUTXOs = sortSpendableUTXOs(by: { $0.value > $1.value },
                                             tokenSelectionPolicy: configuration.tokenSelectionPolicy)
        let minimumRelayFeeRate = OpalBase.Transaction.minimumRelayFeeRate
        let selector = CoinSelectorModel(utxos: sortedUTXOs,
                                    configuration: configuration,
                                    targetAmount: targetAmount.uint64,
                                    feePerByte: feePerByte,
                                    minimumRelayFeeRate: minimumRelayFeeRate)
        return try selector.select()
    }
}

