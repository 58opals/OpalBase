// OpalBase+Hedge+FundingRecord.swift

extension _OpalBase.Hedge {
    public struct FundingRecord: Sendable, Equatable {
        public let fundingAddress: OpalBase.Address
        public let fundingAmount: OpalBase.Satoshi
        public let fundingTransactionHash: OpalBase.Transaction.Hash
        public let fundingTransactionHashHex: String
        public let fundingOutputIndex: UInt32
        public let dataDocumentJSON: String

        public init(
            fundingAddress: OpalBase.Address,
            fundingAmount: OpalBase.Satoshi,
            fundingTransactionHash: OpalBase.Transaction.Hash,
            fundingOutputIndex: UInt32,
            dataDocumentJSON: String
        ) {
            self.fundingAddress = fundingAddress
            self.fundingAmount = fundingAmount
            self.fundingTransactionHash = fundingTransactionHash
            self.fundingTransactionHashHex = fundingTransactionHash.reverseOrder.hexadecimalString
            self.fundingOutputIndex = fundingOutputIndex
            self.dataDocumentJSON = dataDocumentJSON
        }
    }
}
