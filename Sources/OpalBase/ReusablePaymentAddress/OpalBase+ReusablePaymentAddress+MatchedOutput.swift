// OpalBase+ReusablePaymentAddress+MatchedOutput.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// Exact transaction-output data retained independently of current UTXO
    /// status.
    public struct MatchedOutput: Codable, Hashable, Sendable {
        public let transactionHash: OpalBase.Transaction.Hash
        public let outputIndex: UInt32
        public let value: UInt64
        public let lockingScript: Data
        public let tokenData: OpalBase.CashTokens.TokenData?

        public var outpoint: OpalBase.Transaction.Outpoint {
            .init(
                transactionHash: transactionHash,
                outputIndex: outputIndex
            )
        }

        public var transactionOutput: OpalBase.Transaction.Output {
            .init(
                value: value,
                lockingScript: lockingScript,
                tokenData: tokenData
            )
        }

        init(match: Match) {
            self.transactionHash = match.transactionHash
            self.outputIndex = match.outputIndex
            self.value = match.output.value
            self.lockingScript = match.output.lockingScript
            self.tokenData = match.output.tokenData
        }
    }
}
