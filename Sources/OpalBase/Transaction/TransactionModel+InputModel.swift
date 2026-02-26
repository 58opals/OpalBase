// TransactionModel+InputModel.swift

import Foundation

extension TransactionModel {
    public struct InputModel {
        public let previousTransactionHash: TransactionModel.HashModel
        public let previousTransactionOutputIndex: UInt32
        public let unlockingScript: Data
        public let sequence: UInt32
        
        private var unlockingScriptLength: CompactSizeModel {
            CompactSizeModel(value: UInt64(unlockingScript.count))
        }
        
        /// Initializes a TransactionModel.InputModel instance.
        /// - Parameters:
        ///   - previousTransactionHash: The hash of the previous transaction.
        ///   - previousTransactionOutputIndex: The index of the previous output.
        ///   - unlockingScript: The contents of the unlocking script.
        ///   - sequence: The sequence number.
        public init(previousTransactionHash: TransactionModel.HashModel, previousTransactionOutputIndex: UInt32, unlockingScript: Data, sequence: UInt32 = 0xFFFFFFFF) {
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
            self.unlockingScript = unlockingScript
            self.sequence = sequence
        }
        
        /// Encodes the TransactionModel.InputModel into Data.
        /// - Returns: The encoded data.
        func encode() -> Data {
            var writer = Data.WriterModel()
            writer.writeData(previousTransactionHash.naturalOrder)
            writer.writeLittleEndian(previousTransactionOutputIndex)
            writer.writeCompactSize(unlockingScriptLength)
            writer.writeData(unlockingScript)
            writer.writeLittleEndian(sequence)
            return writer.data
        }
        
        /// Decodes a TransactionModel.InputModel instance from Data.
        /// - Parameter data: The data to decode from.
        /// - Throws: `CompactSizeModel.Error` if decoding fails.
        /// - Returns: A tuple containing the decoded TransactionModel.InputModel and the number of bytes read.
        static func decode(from data: Data) throws -> (input: InputModel, bytesRead: Int) {
            var reader = Data.ReaderModel(data)
            let input = try decode(from: &reader)
            return (input, reader.bytesRead)
        }
        
        static func decode(from reader: inout Data.ReaderModel) throws -> InputModel {
            let previousTransactionHash = try reader.readData(count: 32)
            let previousTransactionIndex: UInt32 = try reader.readLittleEndian()
            let unlockingScriptLength = try reader.readCompactSize()
            let unlockingScript = try reader.readData(count: Int(unlockingScriptLength.value))
            let sequence: UInt32 = try reader.readLittleEndian()
            return InputModel(previousTransactionHash: .init(naturalOrder: previousTransactionHash),
                         previousTransactionOutputIndex: previousTransactionIndex,
                         unlockingScript: unlockingScript,
                         sequence: sequence)
        }
    }
}

extension TransactionModel.InputModel: Sendable {}

extension TransactionModel.InputModel: CustomStringConvertible {
    public var description: String {
        """
        TransactionModel InputModel (sequence: \(sequence)):
            Previous TransactionModel HashModel: \(previousTransactionHash.naturalOrder.hexadecimalString) (↔︎: \(previousTransactionHash.reverseOrder.hexadecimalString))
            Previous TransactionModel OutputModel Index: \(previousTransactionOutputIndex)
            Unlocking ScriptModel: \(unlockingScript.hexadecimalString)
        """
    }
}
