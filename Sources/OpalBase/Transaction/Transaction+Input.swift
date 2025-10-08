// Transaction+Input.swift

import Foundation

extension Transaction {
    public struct Input {
        public let previousTransactionHash: Transaction.Hash
        public let previousTransactionOutputIndex: UInt32
        let unlockingScriptLength: CompactSize
        public let unlockingScript: Data
        public let sequence: UInt32
        
        /// Initializes a Transaction.Input instance.
        /// - Parameters:
        ///   - previousTransactionHash: The hash of the previous transaction.
        ///   - previousTransactionOutputIndex: The index of the previous output.
        ///   - unlockingScript: The contents of the unlocking script.
        ///   - sequence: The sequence number.
        init(previousTransactionHash: Transaction.Hash, previousTransactionOutputIndex: UInt32, unlockingScript: Data, sequence: UInt32 = 0xFFFFFFFF) {
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
            self.unlockingScriptLength = CompactSize(value: UInt64(unlockingScript.count))
            self.unlockingScript = unlockingScript
            self.sequence = sequence
        }
        
        /// Encodes the Transaction.Input into Data.
        /// - Returns: The encoded data.
        func encode() -> Data {
            var data = Data()
            data.append(previousTransactionHash.naturalOrder)
            data.append(previousTransactionOutputIndex.littleEndianData)
            data.append(unlockingScriptLength.encode())
            data.append(unlockingScript)
            data.append(sequence.littleEndianData)
            return data
        }
        
        /// Decodes a Transaction.Input instance from Data.
        /// - Parameter data: The data to decode from.
        /// - Throws: `CompactSize.Error` if decoding fails.
        /// - Returns: A tuple containing the decoded Transaction.Input and the number of bytes read.
        static func decode(from data: Data) throws -> (input: Input, bytesRead: Int) {
            var index = data.startIndex
            
            let hashUpperBound = index.advanced(by: 32)
            guard hashUpperBound <= data.endIndex else { throw Data.Error.indexOutOfRange }
            let previousTransactionHash = Data(data[index..<hashUpperBound])
            index = hashUpperBound
            
            let (previousTransactionIndex, newIndex1): (UInt32, Data.Index) = try data.extractValue(from: index)
            index = newIndex1
            
            let (unlockingScriptLength, unlockingScriptLengthSize) = try CompactSize.decode(from: data[index...])
            index += unlockingScriptLengthSize
            
            let scriptLength = Int(unlockingScriptLength.value)
            let scriptUpperBound = index.advanced(by: scriptLength)
            guard scriptUpperBound <= data.endIndex else { throw Data.Error.indexOutOfRange }
            let unlockingScript = Data(data[index..<scriptUpperBound])
            index = scriptUpperBound
            
            let (sequence, newIndex2): (UInt32, Data.Index) = try data.extractValue(from: index)
            index = newIndex2
            
            let input = Input(previousTransactionHash: .init(naturalOrder: previousTransactionHash), previousTransactionOutputIndex: previousTransactionIndex, unlockingScript: unlockingScript, sequence: sequence)
            
            return (input, index - data.startIndex)
        }
    }
}

extension Transaction.Input: Sendable {}

extension Transaction.Input: CustomStringConvertible {
    public var description: String {
        """
        Transaction Input (sequence: \(sequence)):
            Previous Transaction Hash: \(previousTransactionHash.naturalOrder.hexadecimalString) (↔︎: \(previousTransactionHash.reverseOrder.hexadecimalString))
            Previous Transaction Output Index: \(previousTransactionOutputIndex)
            Unlocking Script: \(unlockingScript.hexadecimalString)
        """
    }
}
