import Foundation

extension Transaction {
    public struct Output {
        let value: UInt64
        let lockingScriptLength: CompactSize
        let lockingScript: Data
        
        /// Initializes a Transaction.Output instance.
        /// - Parameters:
        ///   - value: The number of satoshis to be transferred.
        ///   - lockingScript: The contents of the locking script.
        init(value: UInt64, lockingScript: Data) {
            self.value = value
            self.lockingScriptLength = CompactSize(value: UInt64(lockingScript.count))
            self.lockingScript = lockingScript
        }
        
        /// Initializes a Transaction.Output instance.
        /// - Parameters:
        ///   - value: The number of satoshis to be transferred.
        ///   - address: The address of output's recipient.
        init(value: UInt64, address: Address) {
            self.value = value
            self.lockingScript = address.lockingScript.data
            self.lockingScriptLength = CompactSize(value: UInt64(lockingScript.count))
        }
        
        /// Encodes the Transaction.Output into Data.
        /// - Returns: The encoded data.
        func encode() -> Data {
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
            
            let (value, newIndex1): (UInt64, Data.Index) = data.extractValue(from: index)
            index = newIndex1
            
            let (lockingScriptLength, lockingScriptLengthSize) = try CompactSize.decode(from: data[index...])
            index += lockingScriptLengthSize
            
            let lockingScript = data[index..<index + Int(lockingScriptLength.value)]
            index += lockingScript.count
            
            let output = Output(value: value, lockingScript: lockingScript)
            
            return (output, index - data.startIndex)
        }
    }
}

extension Transaction.Output: CustomStringConvertible {
    public var description: String {
        """
        Transaction Output:
            Value: \(value)
            Locking Script: \(lockingScript.hexadecimalString)
        """
    }
}
