// Transaction+Output.swift

import Foundation

extension Transaction {
    public struct Output {
        public let value: UInt64
        public let lockingScript: Data
        
        var lockingScriptLength: CompactSize {
            CompactSize(value: UInt64(lockingScript.count))
        }
        
        /// Initializes a Transaction.Output instance.
        /// - Parameters:
        ///   - value: The number of satoshi to be transferred.
        ///   - lockingScript: The contents of the locking script.
        public init(value: UInt64, lockingScript: Data) {
            self.value = value
            self.lockingScript = lockingScript
        }
        
        /// Initializes a Transaction.Output instance.
        /// - Parameters:
        ///   - value: The number of satoshi to be transferred.
        ///   - address: The address of the output's recipient.
        public init(value: UInt64, address: Address) {
            self.value = value
            self.lockingScript = address.lockingScript.data
        }
        
        /// Encodes the Transaction.Output into Data.
        /// - Returns: The encoded data.
        public func encode() -> Data {
            var writer = Data.Writer()
            writer.writeLittleEndian(value)
            writer.writeCompactSize(lockingScriptLength)
            writer.writeData(lockingScript)
            return writer.data
        }
        
        /// Decodes a Transaction.Output instance from Data.
        /// - Parameter data: The data to decode from.
        /// - Throws: `CompactSize.Error` if decoding fails.
        /// - Returns: A tuple containing the decoded Transaction.Output and the number of bytes read.
        static func decode(from data: Data) throws -> (output: Output, bytesRead: Int) {
            var reader = Data.Reader(data)
            let output = try decode(from: &reader)
            return (output, reader.bytesRead)
        }
        
        static func decode(from reader: inout Data.Reader) throws -> Output {
            let value: UInt64 = try reader.readLittleEndian()
            let lockingScriptLength = try reader.readCompactSize()
            let lockingScript = try reader.readData(count: Int(lockingScriptLength.value))
            return Output(value: value, lockingScript: lockingScript)
        }
    }
}

extension Transaction.Output: Sendable {}
extension Transaction.Output: Equatable {}

extension Transaction.Output: CustomStringConvertible {
    public var description: String {
        """
        Transaction Output:
            Value: \(value)
            Locking Script: \(lockingScript.hexadecimalString)
        """
    }
}
