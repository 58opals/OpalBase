// OpalBase+Hedge+FundingReview.swift

import Foundation

extension _OpalBase.Hedge {
    public struct FundingReview: Sendable {
        public let transaction: OpalBase.Transaction
        public let rawTransactionData: Data
        public let rawTransactionByteCount: Int
        public let fee: OpalBase.Satoshi
        public let change: OpalBase.Account.SpendPlan.TransactionResult.Change?
        public let fundingOutputIndex: UInt32
        public let fundingOutput: OpalBase.Transaction.Output
        public let quote: FundingQuote

        public init(
            transaction: OpalBase.Transaction,
            rawTransactionData: Data,
            fee: OpalBase.Satoshi,
            change: OpalBase.Account.SpendPlan.TransactionResult.Change?,
            fundingOutputIndex: UInt32,
            fundingOutput: OpalBase.Transaction.Output,
            quote: FundingQuote
        ) {
            self.transaction = transaction
            self.rawTransactionData = Data(rawTransactionData)
            self.rawTransactionByteCount = self.rawTransactionData.count
            self.fee = fee
            self.change = change
            self.fundingOutputIndex = fundingOutputIndex
            self.fundingOutput = fundingOutput
            self.quote = quote
        }
    }
}
