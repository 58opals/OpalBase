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
        ///   - value: The number of satoshis to be transferred.
        ///   - lockingScript: The contents of the locking script.
        public init(value: UInt64, lockingScript: Data) {
            self.value = value
            self.lockingScript = lockingScript
        }
        
        /// Initializes a Transaction.Output instance.
        /// - Parameters:
        ///   - value: The number of satoshis to be transferred.
        ///   - address: The address of the output's recipient.
        public init(value: UInt64, address: Address) {
            self.value = value
            self.lockingScript = address.lockingScript.data
        }
        
        /// Encodes the Transaction.Output into Data.
        /// - Returns: The encoded data.
        public func encode() -> Data {
            var data = Data()
            data.append(value.littleEndianData)
            data.append(lockingScriptLength.encode())
            data.append(lockingScript)
            return data
        }
        
        /// Decodes a Transaction.Output instance from Data.
        /// - Parameter data: The data to decode from.
        /// - Throws: `CompactSize.Error` if decoding fails.
        /// - Returns: A tuple containing the decoded Transaction.Output and the number of bytes read.
        static func decode(from data: Data) throws -> (output: Output, bytesRead: Int) {
            var index = data.startIndex
            
            let (value, newIndex1): (UInt64, Data.Index) = try data.extractValue(from: index)
            index = newIndex1
            
            let (lockingScriptLength, lockingScriptLengthSize) = try CompactSize.decode(from: data[index...])
            index += lockingScriptLengthSize
            
            let scriptLength = Int(lockingScriptLength.value)
            let scriptUpperBound = index.advanced(by: scriptLength)
            guard scriptUpperBound <= data.endIndex else { throw Data.Error.indexOutOfRange }
            let lockingScript = Data(data[index..<scriptUpperBound])
            index = scriptUpperBound
            
            let output = Output(value: value, lockingScript: lockingScript)
            
            return (output, index - data.startIndex)
        }
    }
}

extension Transaction.Output: Sendable {}

extension Transaction.Output: CustomStringConvertible {
    public var description: String {
        """
        Transaction Output:
            Value: \(value)
            Locking Script: \(lockingScript.hexadecimalString)
        """
    }
}
