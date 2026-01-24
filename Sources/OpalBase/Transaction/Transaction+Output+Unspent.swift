// Transaction+Output+Unspent.swift

import Foundation

extension Transaction.Output {
    public struct Unspent {
        public let previousTransactionHash: Transaction.Hash
        public let previousTransactionOutputIndex: UInt32
        public let value: UInt64
        public let lockingScript: Data
        public let tokenData: CashTokens.TokenData?
        
        public init(value: UInt64,
                    lockingScript: Data,
                    tokenData: CashTokens.TokenData? = nil,
                    previousTransactionHash: Transaction.Hash,
                    previousTransactionOutputIndex: UInt32) {
            self.value = value
            self.lockingScript = lockingScript
            self.tokenData = tokenData
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
        
        public init(output: Transaction.Output, previousTransactionHash: Transaction.Hash, previousTransactionOutputIndex: UInt32) {
            self.value = output.value
            self.lockingScript = output.lockingScript
            self.tokenData = output.tokenData
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
    }
}

extension Transaction.Output.Unspent: Sendable {}
extension Transaction.Output.Unspent: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(previousTransactionHash)
        hasher.combine(previousTransactionOutputIndex)
    }
}
extension Transaction.Output.Unspent: Equatable {
    public static func == (lhs: Transaction.Output.Unspent, rhs: Transaction.Output.Unspent) -> Bool {
        lhs.previousTransactionHash == rhs.previousTransactionHash
        && lhs.previousTransactionOutputIndex == rhs.previousTransactionOutputIndex
    }
}

extension Transaction.Output.Unspent {
    func compareOrder(before other: Transaction.Output.Unspent) -> Bool {
        let leftHash = previousTransactionHash.naturalOrder
        let rightHash = other.previousTransactionHash.naturalOrder
        if leftHash == rightHash {
            return previousTransactionOutputIndex < other.previousTransactionOutputIndex
        }
        return leftHash.lexicographicallyPrecedes(rightHash)
    }
}

extension Transaction.Output.Unspent: CustomStringConvertible {
    public var description: String {
        """
        Unspent Transaction Output:
            Previous Transaction Hash: \(previousTransactionHash.naturalOrder.hexadecimalString) (↔︎: \(previousTransactionHash.reverseOrder.hexadecimalString))
            Previous Transaction Output Index: \(previousTransactionOutputIndex)
            Value: \(value)
            Locking Script: \(lockingScript.hexadecimalString)
            Token Data: \(tokenData.map(String.init(describing:)) ?? "none")
        """
    }
}
