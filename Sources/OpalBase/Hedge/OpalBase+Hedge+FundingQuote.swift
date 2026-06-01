// OpalBase+Hedge+FundingQuote.swift

import Foundation

extension _OpalBase.Hedge {
    public struct FundingQuote: Sendable, Equatable {
        public let fundingAddress: OpalBase.Address
        public let fundingAmount: OpalBase.Satoshi
        public let payoutAmount: OpalBase.Satoshi
        public let dustReserveAmount: OpalBase.Satoshi
        public let redeemScriptBytecode: Data
        public let contractDataDocumentJSON: String

        public init(
            fundingAddress: OpalBase.Address,
            fundingAmount: OpalBase.Satoshi,
            payoutAmount: OpalBase.Satoshi,
            dustReserveAmount: OpalBase.Satoshi,
            redeemScriptBytecode: Data,
            contractDataDocumentJSON: String
        ) {
            self.fundingAddress = fundingAddress
            self.fundingAmount = fundingAmount
            self.payoutAmount = payoutAmount
            self.dustReserveAmount = dustReserveAmount
            self.redeemScriptBytecode = Data(redeemScriptBytecode)
            self.contractDataDocumentJSON = contractDataDocumentJSON
        }
    }
}
