// Account~TokenOutput.swift

import Foundation

extension Account {
    func makeTokenOutput(
        address: Address,
        tokenData: CashTokens.TokenData,
        overrideAmount: Satoshi? = nil,
        minimumRelayFeeRate: UInt64 = Transaction.minimumRelayFeeRate,
        mapDustError: (Swift.Error) -> Account.Error
    ) throws -> Transaction.Output {
        let template = Transaction.Output(value: 0, address: address, tokenData: tokenData)
        
        let dust: UInt64
        do {
            dust = try template.dustThreshold(feeRate: minimumRelayFeeRate)
        } catch {
            throw mapDustError(error)
        }
        
        let value = overrideAmount?.uint64 ?? dust
        return Transaction.Output(value: value, address: address, tokenData: tokenData)
    }
}
