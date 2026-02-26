// TransactionModel+OutputModel+UnspentModel.swift

import Foundation

extension TransactionModel.OutputModel {
    public struct UnspentModel {
        public let previousTransactionHash: TransactionModel.HashModel
        public let previousTransactionOutputIndex: UInt32
        public let value: UInt64
        public let lockingScript: Data
        public let tokenData: CashTokensModel.TokenData?
        
        public init(value: UInt64,
                    lockingScript: Data,
                    tokenData: CashTokensModel.TokenData? = nil,
                    previousTransactionHash: TransactionModel.HashModel,
                    previousTransactionOutputIndex: UInt32) {
            self.value = value
            self.lockingScript = lockingScript
            self.tokenData = tokenData
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
        
        public init(output: TransactionModel.OutputModel, previousTransactionHash: TransactionModel.HashModel, previousTransactionOutputIndex: UInt32) {
            self.value = output.value
            self.lockingScript = output.lockingScript
            self.tokenData = output.tokenData
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
    }
}

extension TransactionModel.OutputModel.UnspentModel: Sendable {}
extension TransactionModel.OutputModel.UnspentModel: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(previousTransactionHash)
        hasher.combine(previousTransactionOutputIndex)
    }
}
extension TransactionModel.OutputModel.UnspentModel: Equatable {
    public static func == (lhs: TransactionModel.OutputModel.UnspentModel, rhs: TransactionModel.OutputModel.UnspentModel) -> Bool {
        lhs.previousTransactionHash == rhs.previousTransactionHash
        && lhs.previousTransactionOutputIndex == rhs.previousTransactionOutputIndex
    }
}

extension TransactionModel.OutputModel.UnspentModel {
    func compareOrder(before other: TransactionModel.OutputModel.UnspentModel) -> Bool {
        let leftHash = previousTransactionHash.naturalOrder
        let rightHash = other.previousTransactionHash.naturalOrder
        if leftHash == rightHash {
            return previousTransactionOutputIndex < other.previousTransactionOutputIndex
        }
        return leftHash.lexicographicallyPrecedes(rightHash)
    }
}

extension TransactionModel.OutputModel.UnspentModel: CustomStringConvertible {
    public var description: String {
        """
        UnspentModel TransactionModel OutputModel:
            Previous TransactionModel HashModel: \(previousTransactionHash.naturalOrder.hexadecimalString) (↔︎: \(previousTransactionHash.reverseOrder.hexadecimalString))
            Previous TransactionModel OutputModel Index: \(previousTransactionOutputIndex)
            Value: \(value)
            Locking ScriptModel: \(lockingScript.hexadecimalString)
            Token Data: \(tokenData.map(String.init(describing:)) ?? "none")
        """
    }
}
