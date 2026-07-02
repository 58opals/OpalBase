// OpalBase+Transaction+Output+Unspent.swift

import Foundation

extension _OpalBase.Transaction.Output {
    public struct Unspent {
        public let previousTransactionHash: OpalBase.Transaction.Hash
        public let previousTransactionOutputIndex: UInt32
        public let value: UInt64
        public let lockingScript: Data
        public let tokenData: OpalBase.CashTokens.TokenData?
        
        public init(value: UInt64,
                    lockingScript: Data,
                    tokenData: OpalBase.CashTokens.TokenData? = nil,
                    previousTransactionHash: OpalBase.Transaction.Hash,
                    previousTransactionOutputIndex: UInt32) {
            self.value = value
            self.lockingScript = Data(lockingScript)
            self.tokenData = tokenData
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
        
        public init(output: OpalBase.Transaction.Output, previousTransactionHash: OpalBase.Transaction.Hash, previousTransactionOutputIndex: UInt32) {
            self.init(
                value: output.value,
                lockingScript: output.lockingScript,
                tokenData: output.tokenData,
                previousTransactionHash: previousTransactionHash,
                previousTransactionOutputIndex: previousTransactionOutputIndex
            )
        }
    }
}

extension _OpalBase.Transaction.Output.Unspent: Sendable {}
extension _OpalBase.Transaction.Output.Unspent: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(previousTransactionHash)
        hasher.combine(previousTransactionOutputIndex)
    }
}
extension _OpalBase.Transaction.Output.Unspent: Equatable {
    public static func == (lhs: OpalBase.Transaction.Output.Unspent, rhs: OpalBase.Transaction.Output.Unspent) -> Bool {
        lhs.previousTransactionHash == rhs.previousTransactionHash
        && lhs.previousTransactionOutputIndex == rhs.previousTransactionOutputIndex
    }
}

extension _OpalBase.Transaction.Output.Unspent {
    func compareOrder(before other: OpalBase.Transaction.Output.Unspent) -> Bool {
        let leftHash = previousTransactionHash.reverseOrder
        let rightHash = other.previousTransactionHash.reverseOrder
        if leftHash == rightHash {
            return previousTransactionOutputIndex < other.previousTransactionOutputIndex
        }
        return leftHash.lexicographicallyPrecedes(rightHash)
    }

    func hasSameOutpointAndPayload(as other: OpalBase.Transaction.Output.Unspent) -> Bool {
        previousTransactionHash == other.previousTransactionHash
            && previousTransactionOutputIndex == other.previousTransactionOutputIndex
            && value == other.value
            && lockingScript == other.lockingScript
            && tokenData == other.tokenData
    }
}

extension _OpalBase.Transaction.Output.Unspent: CustomStringConvertible {
    public var description: String {
        """
        Unspent OpalBase.Transaction Output:
            Previous OpalBase.Transaction Hash: \(previousTransactionHash.naturalOrder.hexadecimalString) (↔︎: \(previousTransactionHash.reverseOrder.hexadecimalString))
            Previous OpalBase.Transaction Output Index: \(previousTransactionOutputIndex)
            Value: \(value)
            Locking OpalBase.Script: \(lockingScript.hexadecimalString)
            Token Data: \(tokenData.map(String.init(describing:)) ?? "none")
        """
    }
}
