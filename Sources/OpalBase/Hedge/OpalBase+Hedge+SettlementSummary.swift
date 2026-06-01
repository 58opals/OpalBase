// OpalBase+Hedge+SettlementSummary.swift

extension _OpalBase.Hedge {
    public struct SettlementSummary: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case maturation
            case liquidation
            case mutual
        }

        public let kind: Kind
        public let fundingTransactionHash: OpalBase.Transaction.Hash
        public let fundingTransactionHashHex: String
        public let fundingOutputIndex: UInt32
        public let fundingAmount: OpalBase.Satoshi
        public let settlementTransactionHash: OpalBase.Transaction.Hash
        public let settlementTransactionHashHex: String
        public let settlementPrice: Int64
        public let hedgePayoutAmount: OpalBase.Satoshi
        public let longPayoutAmount: OpalBase.Satoshi
        public let totalPayoutAmount: OpalBase.Satoshi
        public let minerFeeAmount: OpalBase.Satoshi
        public let previousOracleMessageHex: String
        public let previousOracleSignatureHex: String
        public let previousOracleTimestamp: Int64
        public let previousOracleSequence: Int64
        public let settlementOracleMessageHex: String
        public let settlementOracleSignatureHex: String
        public let settlementOracleTimestamp: Int64
        public let settlementOracleSequence: Int64
        public let dataDocumentJSON: String

        public init(
            kind: Kind,
            fundingTransactionHash: OpalBase.Transaction.Hash,
            fundingOutputIndex: UInt32,
            fundingAmount: OpalBase.Satoshi,
            settlementTransactionHash: OpalBase.Transaction.Hash,
            settlementPrice: Int64,
            hedgePayoutAmount: OpalBase.Satoshi,
            longPayoutAmount: OpalBase.Satoshi,
            totalPayoutAmount: OpalBase.Satoshi,
            minerFeeAmount: OpalBase.Satoshi,
            previousOracleMessageHex: String,
            previousOracleSignatureHex: String,
            previousOracleTimestamp: Int64,
            previousOracleSequence: Int64,
            settlementOracleMessageHex: String,
            settlementOracleSignatureHex: String,
            settlementOracleTimestamp: Int64,
            settlementOracleSequence: Int64,
            dataDocumentJSON: String
        ) {
            self.kind = kind
            self.fundingTransactionHash = fundingTransactionHash
            self.fundingTransactionHashHex = fundingTransactionHash.reverseOrder.hexadecimalString
            self.fundingOutputIndex = fundingOutputIndex
            self.fundingAmount = fundingAmount
            self.settlementTransactionHash = settlementTransactionHash
            self.settlementTransactionHashHex = settlementTransactionHash.reverseOrder.hexadecimalString
            self.settlementPrice = settlementPrice
            self.hedgePayoutAmount = hedgePayoutAmount
            self.longPayoutAmount = longPayoutAmount
            self.totalPayoutAmount = totalPayoutAmount
            self.minerFeeAmount = minerFeeAmount
            self.previousOracleMessageHex = previousOracleMessageHex
            self.previousOracleSignatureHex = previousOracleSignatureHex
            self.previousOracleTimestamp = previousOracleTimestamp
            self.previousOracleSequence = previousOracleSequence
            self.settlementOracleMessageHex = settlementOracleMessageHex
            self.settlementOracleSignatureHex = settlementOracleSignatureHex
            self.settlementOracleTimestamp = settlementOracleTimestamp
            self.settlementOracleSequence = settlementOracleSequence
            self.dataDocumentJSON = dataDocumentJSON
        }
    }
}
