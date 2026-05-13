// OpalBase+Transaction+Input.swift

import Foundation

extension _OpalBase.Transaction {
    public struct Input {
        public let previousTransactionHash: OpalBase.Transaction.Hash
        public let previousTransactionOutputIndex: UInt32
        public let unlockingScript: Data
        public let sequence: UInt32
        
        private var unlockingScriptLength: CompactSize {
            CompactSize(value: UInt64(unlockingScript.count))
        }
        
        /// Initializes an OpalBase.Transaction.Input instance.
        /// - Parameters:
        ///   - previousTransactionHash: The hash of the previous transaction.
        ///   - previousTransactionOutputIndex: The index of the previous output.
        ///   - unlockingScript: The contents of the unlocking script.
        ///   - sequence: The sequence number.
        public init(previousTransactionHash: OpalBase.Transaction.Hash, previousTransactionOutputIndex: UInt32, unlockingScript: Data, sequence: UInt32 = 0xFFFFFFFF) {
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionOutputIndex
            self.unlockingScript = unlockingScript
            self.sequence = sequence
        }
        
        /// Encodes the OpalBase.Transaction.Input into Data.
        /// - Returns: The encoded data.
        func encode() -> Data {
            var writer = Data.Writer()
            writer.writeData(previousTransactionHash.naturalOrder)
            writer.writeLittleEndian(previousTransactionOutputIndex)
            writer.writeCompactSize(unlockingScriptLength)
            writer.writeData(unlockingScript)
            writer.writeLittleEndian(sequence)
            return writer.data
        }
        
        /// Decodes an OpalBase.Transaction.Input instance from Data.
        /// - Parameter data: The data to decode from.
        /// - Throws: `CompactSize.Error` if the unlocking script length prefix is invalid, or `Data.Error` if the payload is truncated or the declared lengths exceed the available data.
        /// - Returns: A tuple containing the decoded OpalBase.Transaction.Input and the number of bytes read.
        static func decode(from data: Data) throws -> (input: Input, bytesRead: Int) {
            var reader = Data.Reader(data)
            let input = try decode(from: &reader)
            return (input, reader.bytesRead)
        }
        
        static func decode(from reader: inout Data.Reader) throws -> Input {
            let previousTransactionHash = try reader.readData(count: 32)
            let previousTransactionIndex: UInt32 = try reader.readLittleEndian()
            let unlockingScriptLength = try reader.readCompactSize()
            guard unlockingScriptLength.value <= UInt64(Int.max) else {
                throw Data.Error.indexOutOfRange
            }
            let unlockingScript = try reader.readData(count: Int(unlockingScriptLength.value))
            let sequence: UInt32 = try reader.readLittleEndian()
            return Input(previousTransactionHash: .init(naturalOrder: previousTransactionHash),
                         previousTransactionOutputIndex: previousTransactionIndex,
                         unlockingScript: unlockingScript,
                         sequence: sequence)
        }
    }
}

extension _OpalBase.Transaction.Input: Sendable {}

extension _OpalBase.Transaction.Input {
    var isCoinbase: Bool {
        previousTransactionHash.naturalOrder == Data(
            repeating: 0x00,
            count: OpalBase.Transaction.Hash.expectedByteCount
        )
        && previousTransactionOutputIndex == UInt32.max
    }
}

extension _OpalBase.Transaction.Input: CustomStringConvertible {
    public var description: String {
        """
        OpalBase.Transaction Input (sequence: \(sequence)):
            Previous OpalBase.Transaction Hash: \(previousTransactionHash.naturalOrder.hexadecimalString) (↔︎: \(previousTransactionHash.reverseOrder.hexadecimalString))
            Previous OpalBase.Transaction Output Index: \(previousTransactionOutputIndex)
            Unlocking OpalBase.Script: \(unlockingScript.hexadecimalString)
        """
    }
}
