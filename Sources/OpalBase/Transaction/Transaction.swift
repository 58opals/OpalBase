// Transaction.swift

import Foundation

/// A Bitcoin Cash transaction containing version, inputs, outputs, and lock time.
///
/// - Parameters:
///   - version: The transaction version.
///   - inputs: The transaction inputs.
///   - outputs: The transaction outputs.
///   - lockTime: The transaction lock time.
public struct Transaction {
    public let version: UInt32
    public let inputs: [Input]
    public let outputs: [Output]
    public let lockTime: UInt32
    
    /// Initializes a Transaction instance.
    /// - Parameters:
    ///   - version: The transaction version.
    ///   - inputs: The list of inputs.
    ///   - outputs: The list of outputs.
    ///   - lockTime: The lock time.
    public init(version: UInt32, inputs: [Input], outputs: [Output], lockTime: UInt32) {
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.lockTime = lockTime
    }
    
    /// Encodes the Transaction into Data.
    /// - Returns: The encoded data.
    public func encode() throws -> Data {
        try makeSerializedTransaction(with: inputs)
    }
    
    /// Decodes a Transaction instance from Data.
    /// - Parameter data: The data to decode from.
    /// - Returns: A tuple containing the decoded Transaction and the number of bytes read.
    /// - Throws: `CompactSize.Error` if decoding fails.
    public static func decode(from data: Data) throws -> (transaction: Transaction, bytesRead: Int) {
        var reader = Data.Reader(data)
        let transaction = try decode(from: &reader)
        return (transaction, reader.bytesRead)
    }
    
    static func decode(from reader: inout Data.Reader) throws -> Transaction {
        let version: UInt32 = try reader.readLittleEndian()
        let inputsCount = try reader.readCompactSize()
        let inputs = try (0..<inputsCount.value).map { _ -> Input in
            try Input.decode(from: &reader)
        }
        
        let outputsCount = try reader.readCompactSize()
        let outputs = try (0..<outputsCount.value).map { _ -> Output in
            try Output.decode(from: &reader)
        }
        
        let lockTime: UInt32 = try reader.readLittleEndian()
        return Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
    }
}

extension Transaction {
    func makeSerializedTransaction(with inputs: [Input]) throws -> Data {
        var writer = Data.Writer()
        writer.writeLittleEndian(version)
        writer.writeCompactSize(CompactSize(value: UInt64(inputs.count)))
        inputs.forEach { writer.writeData($0.encode()) }
        writer.writeCompactSize(CompactSize(value: UInt64(outputs.count)))
        for output in outputs {
            writer.writeData(try output.encode())
        }
        writer.writeLittleEndian(lockTime)
        return writer.data
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
        public let transactionHash: Transaction.Hash
        public let height: UInt32?
        public let fee: UInt64?
    }
    
    /// A detailed representation of a transaction.
    ///
    /// - Parameters:
    ///   - transaction: The full transaction.
    ///   - blockHash: The block hash if confirmed.
    ///   - blockTime: The block time if confirmed.
    ///   - confirmations: The number of confirmations.
    ///   - hash: The transaction hash.
    ///   - rawTransactionData: The raw transaction payload as returned by the network.
    ///   - size: The transaction size in bytes.
    ///   - time: The transaction time if available.
    public struct Detailed {
        public let transaction: Transaction
        
        public let blockHash: Data?
        public let blockTime: UInt32?
        public let confirmations: UInt32?
        public let hash: Transaction.Hash
        public let rawTransactionData: Data
        public let size: UInt32
        public let time: UInt32?
    }
}

extension Transaction {
    public enum Error: Swift.Error, Equatable {
        case insufficientFunds(required: UInt64)
        case accountNotFound
        case cannotCreateTransaction
        case cannotBroadcastTransaction
        case unsupportedHashType
        case unsupportedSignatureFormat
        case outputValueIsLessThanTheDustLimit
        case sighashSingleIndexOutOfRange
        case transactionNotFound
        case feeCalculationOverflow(size: Int, feePerByte: UInt64)
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
        var description = "Simplified Transaction: \(transactionHash.naturalOrder.hexadecimalString)"
        
        if let height {
            description += " at \(height)"
        } else {
            description += " (unconfirmed)"
        }
        
        if let fee {
            description += " with \(fee) fee"
        }
        
        return description
    }
}

// MARK: - Legacy reference implementation
/// The following implementation is preserved for educational purposes. It mirrors an earlier iteration of `Transaction` that demonstrated how Bitcoin Cash transactions are serialized and sized without relying on helper methods. The snippet highlights each field that becomes part of the payload so readers can follow the binary layout step by step.
private extension Transaction {
    func encode_Legacy() throws -> Data {
        var data = Data()
        
        data.append(version.littleEndianData)
        
        data.append(CompactSize(value: UInt64(inputs.count)).encode())
        inputs.forEach { data.append($0.encode()) }
        
        data.append(CompactSize(value: UInt64(outputs.count)).encode())
        for output in outputs {
            data.append(try output.encode())
        }
        
        data.append(lockTime.littleEndianData)
        
        return data
    }
}
