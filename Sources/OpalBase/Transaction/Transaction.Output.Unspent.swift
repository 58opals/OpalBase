import Foundation

extension Transaction.Output {
    public struct Unspent {
        let previousTransactionHash: Transaction.Hash
        let previousTransactionOutputIndex: UInt32
        let value: UInt64
        let lockingScript: Data
        
        init(value: UInt64, lockingScript: Data, previousTransactionHash: Transaction.Hash, previousTransactionOutputIndex: UInt32) {
            self.value = value
            self.lockingScript = lockingScript
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
        
        init(output: Transaction.Output, previousTransactionHash: Transaction.Hash, previousTransactionOutputIndex: UInt32) {
            self.value = output.value
            self.lockingScript = output.lockingScript
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
        }
    }
}

extension Transaction.Output.Unspent: Hashable {}
extension Transaction.Output.Unspent: Sendable {}

extension Transaction.Output.Unspent: CustomStringConvertible {
    public var description: String {
        """
        Unspent Transaction Output:
            Previous Transaction Hash: \(previousTransactionHash.naturalOrder.hexadecimalString) (↔︎: \(previousTransactionHash.reverseOrder.hexadecimalString))
            Previous Transaction Output Index: \(previousTransactionOutputIndex)
            Value: \(value)
            Locking Script: \(lockingScript.hexadecimalString)
        """
    }
}
