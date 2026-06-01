// OpalBase+Address+Book+UTXO.swift

extension _OpalBase.Address.Book {
    func selectUTXOs(targetAmount: OpalBase.Satoshi,
                     feePolicy: OpalBase.Wallet.FeePolicy,
                     recommendationContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
                     override: OpalBase.Wallet.FeePolicy.Override? = nil,
                     configuration: CoinSelection.Configuration = .makeTemplateConfiguration()) throws -> [OpalBase.Transaction.Output.Unspent] {
        let feePerByte = feePolicy.recommendFeeRate(for: recommendationContext, override: override)
        return try selectUTXOs(targetAmount: targetAmount,
                               feePerByte: feePerByte,
                               configuration: configuration)
    }
    
    private func selectUTXOs(targetAmount: OpalBase.Satoshi,
                             feePerByte: UInt64,
                             configuration: CoinSelection.Configuration) throws -> [OpalBase.Transaction.Output.Unspent] {
        let sortedUTXOs = sortSpendableUTXOs(by: compareCoinSelectionOrder,
                                             tokenSelectionPolicy: configuration.tokenSelectionPolicy)
        let minimumRelayFeeRate = OpalBase.Transaction.minimumRelayFeeRate
        let selector = CoinSelector(utxos: sortedUTXOs,
                                    configuration: configuration,
                                    targetAmount: targetAmount.uint64,
                                    feePerByte: feePerByte,
                                    minimumRelayFeeRate: minimumRelayFeeRate)
        return try selector.select()
    }

    private func compareCoinSelectionOrder(_ lhs: OpalBase.Transaction.Output.Unspent,
                                           _ rhs: OpalBase.Transaction.Output.Unspent) -> Bool {
        if lhs.value == rhs.value {
            return lhs.compareOrder(before: rhs)
        }
        return lhs.value > rhs.value
    }
}
