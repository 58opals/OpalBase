// AddressModel+BookActor~UTXO.swift

import Foundation

extension AddressModel.BookActor {
    func selectUTXOs(targetAmount: SatoshiModel,
                     feePolicy: WalletActor.FeePolicy,
                     recommendationContext: WalletActor.FeePolicy.RecommendationContext = .init(),
                     override: WalletActor.FeePolicy.Override? = nil,
                     configuration: CoinSelectionModel.Configuration = .makeTemplateConfiguration()) throws -> [TransactionModel.OutputModel.UnspentModel] {
        let feePerByte = feePolicy.recommendFeeRate(for: recommendationContext, override: override)
        return try selectUTXOs(targetAmount: targetAmount,
                               feePerByte: feePerByte,
                               configuration: configuration)
    }
    
    private func selectUTXOs(targetAmount: SatoshiModel,
                             feePerByte: UInt64,
                             configuration: CoinSelectionModel.Configuration) throws -> [TransactionModel.OutputModel.UnspentModel] {
        let sortedUTXOs = sortSpendableUTXOs(by: { $0.value > $1.value },
                                             tokenSelectionPolicy: configuration.tokenSelectionPolicy)
        let minimumRelayFeeRate = TransactionModel.minimumRelayFeeRate
        let selector = CoinSelectorModel(utxos: sortedUTXOs,
                                    configuration: configuration,
                                    targetAmount: targetAmount.uint64,
                                    feePerByte: feePerByte,
                                    minimumRelayFeeRate: minimumRelayFeeRate)
        return try selector.select()
    }
}

