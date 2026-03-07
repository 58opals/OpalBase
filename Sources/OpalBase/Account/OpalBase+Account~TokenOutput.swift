// OpalBase.Account~TokenOutput.swift

import Foundation

extension _OpalBase.Account {
    func makeTokenOutput(
        address: OpalBase.Address,
        tokenData: OpalBase.CashTokens.TokenData,
        overrideAmount: OpalBase.Satoshi? = nil,
        minimumRelayFeeRate: UInt64 = OpalBase.Transaction.minimumRelayFeeRate,
        mapDustError: (Swift.Error) -> OpalBase.Account.Error
    ) throws -> OpalBase.Transaction.OutputModel {
        let template = OpalBase.Transaction.OutputModel(value: 0, address: address, tokenData: tokenData)
        
        let dust: UInt64
        do {
            dust = try template.calculateDustThreshold(feeRate: minimumRelayFeeRate)
        } catch {
            throw mapDustError(error)
        }
        
        let value = overrideAmount?.uint64 ?? dust
        return OpalBase.Transaction.OutputModel(value: value, address: address, tokenData: tokenData)
    }
}
