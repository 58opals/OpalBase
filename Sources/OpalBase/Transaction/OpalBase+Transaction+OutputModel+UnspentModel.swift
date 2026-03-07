// OpalBase.Transaction+OutputModel+UnspentModel.swift

import Foundation

extension _OpalBase.Transaction.OutputModel {
    public struct UnspentModel {
        public let previousTransactionHash: OpalBase.Transaction.HashModel
        public let previousTransactionOutputIndex: UInt32
        public let value: UInt64
        public let lockingScript: Data
        public let tokenData: OpalBase.CashTokens.TokenData?
        
        public init(value: UInt64,
                    lockingScript: Data,
                    tokenData: OpalBase.CashTokens.TokenData? = nil,
                    previousTransactionHash: OpalBase.Transaction.HashModel,
                    previousTransactionOutputIndex: UInt32) {
            self.value = value
            self.lockingScript = lockingScript
            self.tokenData = tokenData
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
        
        public init(output: OpalBase.Transaction.OutputModel, previousTransactionHash: OpalBase.Transaction.HashModel, previousTransactionOutputIndex: UInt32) {
            self.value = output.value
            self.lockingScript = output.lockingScript
            self.tokenData = output.tokenData
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
    }
}

extension _OpalBase.Transaction.OutputModel.UnspentModel: Sendable {}
extension _OpalBase.Transaction.OutputModel.UnspentModel: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(previousTransactionHash)
        hasher.combine(previousTransactionOutputIndex)
    }
}
extension _OpalBase.Transaction.OutputModel.UnspentModel: Equatable {
    public static func == (lhs: OpalBase.Transaction.OutputModel.UnspentModel, rhs: OpalBase.Transaction.OutputModel.UnspentModel) -> Bool {
        lhs.previousTransactionHash == rhs.previousTransactionHash
        && lhs.previousTransactionOutputIndex == rhs.previousTransactionOutputIndex
    }
}

extension _OpalBase.Transaction.OutputModel.UnspentModel {
    func compareOrder(before other: OpalBase.Transaction.OutputModel.UnspentModel) -> Bool {
        let leftHash = previousTransactionHash.naturalOrder
        let rightHash = other.previousTransactionHash.naturalOrder
        if leftHash == rightHash {
            return previousTransactionOutputIndex < other.previousTransactionOutputIndex
        }
        return leftHash.lexicographicallyPrecedes(rightHash)
    }
}

extension _OpalBase.Transaction.OutputModel.UnspentModel: CustomStringConvertible {
    public var description: String {
        """
        UnspentModel OpalBase.Transaction OutputModel:
            Previous OpalBase.Transaction HashModel: \(previousTransactionHash.naturalOrder.hexadecimalString) (↔︎: \(previousTransactionHash.reverseOrder.hexadecimalString))
            Previous OpalBase.Transaction OutputModel Index: \(previousTransactionOutputIndex)
            Value: \(value)
            Locking OpalBase.Script: \(lockingScript.hexadecimalString)
            Token Data: \(tokenData.map(String.init(describing:)) ?? "none")
        """
    }
}
