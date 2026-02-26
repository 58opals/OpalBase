// AccountActor~TokenOutput.swift

import Foundation

extension AccountActor {
    func makeTokenOutput(
        address: AddressModel,
        tokenData: CashTokensModel.TokenData,
        overrideAmount: SatoshiModel? = nil,
        minimumRelayFeeRate: UInt64 = TransactionModel.minimumRelayFeeRate,
        mapDustError: (Swift.Error) -> AccountActor.Error
    ) throws -> TransactionModel.OutputModel {
        let template = TransactionModel.OutputModel(value: 0, address: address, tokenData: tokenData)
        
        let dust: UInt64
        do {
            dust = try template.calculateDustThreshold(feeRate: minimumRelayFeeRate)
        } catch {
            throw mapDustError(error)
        }
        
        let value = overrideAmount?.uint64 ?? dust
        return TransactionModel.OutputModel(value: value, address: address, tokenData: tokenData)
    }
}
