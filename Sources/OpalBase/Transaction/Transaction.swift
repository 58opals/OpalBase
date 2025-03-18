import Foundation

/// A Bitcoin Cash transaction containing version, inputs, outputs, and lock time.
///
/// - Parameters:
///   - version: The transaction version.
///   - inputs: The transaction inputs.
///   - outputs: The transaction outputs.
///   - lockTime: The transaction lock time.
public struct Transaction {
    let version: UInt32
    let inputs: [Input]
    let outputs: [Output]
    let lockTime: UInt32
    
    /// Initializes a Transaction instance.
    /// - Parameters:
    ///   - version: The transaction version.
    ///   - inputs: The list of inputs.
    ///   - outputs: The list of outputs.
    ///   - lockTime: The lock time.
    init(version: UInt32, inputs: [Input], outputs: [Output], lockTime: UInt32) {
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.lockTime = lockTime
    }
    
    /// Encodes the Transaction into Data.
    /// - Returns: The encoded data.
    func encode() -> Data {
        var data = Data()
        
        data.append(version.littleEndianData)
        
        data.append(CompactSize(value: UInt64(inputs.count)).encode())
        inputs.forEach { data.append($0.encode()) }
        
        data.append(CompactSize(value: UInt64(outputs.count)).encode())
        outputs.forEach { data.append($0.encode()) }
        
        data.append(lockTime.littleEndianData)
        
        return data
    }
    
    /// Decodes a Transaction instance from Data.
    /// - Parameter data: The data to decode from.
    /// - Returns: A tuple containing the decoded Transaction and the number of bytes read.
    /// - Throws: `CompactSize.Error` if decoding fails.
    static func decode(from data: Data) throws -> (transaction: Transaction, bytesRead: Int) {
        var index = data.startIndex
        
        let (version, newIndex1): (UInt32, Data.Index) = data.extractValue(from: index)
        index = newIndex1
        
        let (inputsCount, inputsCountSize) = try CompactSize.decode(from: data[index...])
        index += inputsCountSize
        
        let inputs = try (0..<inputsCount.value).map { _ -> Input in
            let (input, inputSize) = try Input.decode(from: data[index...])
            index += inputSize
            return input
        }
        
        let (outputsCount, outputsCountSize) = try CompactSize.decode(from: data[index...])
        index += outputsCountSize
        
        let outputs = try (0..<outputsCount.value).map { _ -> Output in
            let (output, outputSize) = try Output.decode(from: data[index...])
            index += outputSize
            return output
        }
        
        let (lockTime, newIndex2): (UInt32, Data.Index) = data.extractValue(from: index)
        index = newIndex2
        
        let transaction = Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        
        return (transaction, index)
    }
}

extension Transaction {
    /// A simplified representation of a transaction.
    ///
    /// - Parameters:
    ///   - transactionHash: The transaction hash.
    ///   - height: The block height if confirmed.
    ///   - fee: The transaction fee.
    public struct Simple {
        let transactionHash: Transaction.Hash
        let height: UInt32?
        let fee: UInt64?
    }
    
    /// A detailed representation of a transaction.
    ///
    /// - Parameters:
    ///   - transaction: The full transaction.
    ///   - blockHash: The block hash if confirmed.
    ///   - blockTime: The block time if confirmed.
    ///   - confirmations: The number of confirmations.
    ///   - hash: The transaction hash.
    ///   - hex: The raw transaction data in hex.
    ///   - size: The transaction size in bytes.
    ///   - time: The transaction time if available.
    public struct Detailed {
        let transaction: Transaction
        
        let blockHash: Data?
        let blockTime: UInt32?
        let confirmations: UInt32?
        let hash: Data
        let raw: Data
        let size: UInt32
        let time: UInt32?
    }
}

extension Transaction: Sendable {}
extension Transaction.Simple: Sendable {}
extension Transaction.Detailed: Sendable {}

extension Transaction: CustomStringConvertible {
    public var description: String {
        """
        Transaction (version: \(version), locktime: \(lockTime)):
            Inputs: \(inputs)
            Outputs: \(outputs)
        """
    }
}

extension Transaction.Simple: CustomStringConvertible {
    public var description: String {
        "Simplified Transaction: \(self.transactionHash.naturalOrder.hexadecimalString)" + ((self.height != nil) ? " at \(self.height!)" : "(unconfirmed)") + ((self.fee != nil) ? " with \(self.fee!.description) fee" : "")
    }
}
