import Foundation

extension Transaction {
    struct Input {
        let previousTransactionHash: Data
        let previousTransactionOutputIndex: UInt32
        let unlockingScriptLength: CompactSize
        let unlockingScript: Data
        let sequence: UInt32
        
        /// Initializes a Transaction.Input instance.
        /// - Parameters:
        ///   - previousTransactionHash: The hash of the previous transaction.
        ///   - previousTransactionOutputIndex: The index of the previous output.
        ///   - unlockingScript: The contents of the unlocking script.
        ///   - sequence: The sequence number.
        init(previousTransactionHash: Data, previousTransactionIndex: UInt32, unlockingScript: Data, sequence: UInt32 = 0xFFFFFFFF) {
            self.previousTransactionHash = previousTransactionHash
            self.previousTransactionOutputIndex = previousTransactionIndex
            self.unlockingScriptLength = CompactSize(value: UInt64(unlockingScript.count))
            self.unlockingScript = unlockingScript
            self.sequence = sequence
        }
        
        /// Encodes the Transaction.Input into Data.
        /// - Returns: The encoded data.
        func encode() -> Data {
            var data = Data()
            data.append(previousTransactionHash)
            data.append(contentsOf: withUnsafeBytes(of: previousTransactionOutputIndex.littleEndian, Array.init))
            data.append(unlockingScriptLength.encode())
            data.append(unlockingScript)
            data.append(contentsOf: withUnsafeBytes(of: sequence.littleEndian, Array.init))
            return data
        }
        
        /// Decodes a Transaction.Input instance from Data.
        /// - Parameter data: The data to decode from.
        /// - Throws: `CompactSize.Error` if decoding fails.
        /// - Returns: A tuple containing the decoded Transaction.Input and the number of bytes read.
        static func decode(from data: Data) throws -> (input: Input, bytesRead: Int) {
            var index = data.startIndex
            
            let previousTransactionHash = data[index..<index + 32]
            index += 32
            
            let (previousTransactionIndex, newIndex1): (UInt32, Data.Index) = data.extractValue(from: index)
            index = newIndex1
            
            let (unlockingScriptLength, unlockingScriptLengthSize) = try CompactSize.decode(from: data[index...])
            index += unlockingScriptLengthSize
            
            let unlockingScript = data[index..<index + Int(unlockingScriptLength.value)]
            index += unlockingScript.count
            
            let (sequence, newIndex2): (UInt32, Data.Index) = data.extractValue(from: index)
            index = newIndex2
            
            let input = Input(previousTransactionHash: previousTransactionHash, previousTransactionIndex: previousTransactionIndex, unlockingScript: unlockingScript, sequence: sequence)
            
            return (input, index - data.startIndex)
        }
    }
}
