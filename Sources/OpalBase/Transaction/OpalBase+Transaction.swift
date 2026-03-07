// OpalBase+Transaction.swift

import Foundation

/// A Bitcoin Cash transaction containing version, inputs, outputs, and lock time.
///
/// - Parameters:
///   - version: The transaction version.
///   - inputs: The transaction inputs.
///   - outputs: The transaction outputs.
///   - lockTime: The transaction lock time.
extension OpalBase {
    public struct Transaction {
        public let version: UInt32
        public let inputs: [InputModel]
        public let outputs: [OutputModel]
        public let lockTime: UInt32
        
        /// Initializes a OpalBase.Transaction instance.
        /// - Parameters:
        ///   - version: The transaction version.
        ///   - inputs: The list of inputs.
        ///   - outputs: The list of outputs.
        ///   - lockTime: The lock time.
        public init(version: UInt32, inputs: [InputModel], outputs: [OutputModel], lockTime: UInt32) {
            self.version = version
            self.inputs = inputs
            self.outputs = outputs
            self.lockTime = lockTime
        }
        
        /// Encodes the OpalBase.Transaction into Data.
        /// - Returns: The encoded data.
        public func encode() throws -> Data {
            try makeSerializedTransaction(with: inputs)
        }
        
        /// Decodes a OpalBase.Transaction instance from Data.
        /// - Parameter data: The data to decode from.
        /// - Returns: A tuple containing the decoded OpalBase.Transaction and the number of bytes read.
        /// - Throws: `CompactSizeModel.Error` if decoding fails.
        public static func decode(from data: Data) throws -> (transaction: OpalBase.Transaction, bytesRead: Int) {
            var reader = Data.ReaderModel(data)
            let transaction = try decode(from: &reader)
            return (transaction, reader.bytesRead)
        }
        
        static func decode(from reader: inout Data.ReaderModel) throws -> OpalBase.Transaction {
            let version: UInt32 = try reader.readLittleEndian()
            let inputsCount = try reader.readCompactSize()
            let inputs = try (0..<inputsCount.value).map { _ -> InputModel in
                try InputModel.decode(from: &reader)
            }
            
            let outputsCount = try reader.readCompactSize()
            let outputs = try (0..<outputsCount.value).map { _ -> OutputModel in
                try OutputModel.decode(from: &reader)
            }
            
            let lockTime: UInt32 = try reader.readLittleEndian()
            return OpalBase.Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        }
    }
}

extension _OpalBase.Transaction {
    func makeSerializedTransaction(with inputs: [InputModel]) throws -> Data {
        var writer = Data.WriterModel()
        writer.writeLittleEndian(version)
        writer.writeCompactSize(CompactSizeModel(value: UInt64(inputs.count)))
        inputs.forEach { writer.writeData($0.encode()) }
        writer.writeCompactSize(CompactSizeModel(value: UInt64(outputs.count)))
        for output in outputs {
            writer.writeData(try output.encode())
        }
        writer.writeLittleEndian(lockTime)
        return writer.data
    }
}

extension _OpalBase.Transaction: Sendable {}

extension _OpalBase.Transaction: CustomStringConvertible {
    public var description: String {
        """
        OpalBase.Transaction (version: \(version), locktime: \(lockTime)):
            Inputs: \(inputs)
            Outputs: \(outputs)
        """
    }
}

// MARK: - LegacyModel reference implementation
/// The following implementation is preserved for educational purposes. It mirrors an earlier iteration of `OpalBase.Transaction` that demonstrated how Bitcoin Cash transactions are serialized and sized without relying on helper methods. The snippet highlights each field that becomes part of the payload so readers can follow the binary layout step by step.
private extension _OpalBase.Transaction {
    func encode_Legacy() throws -> Data {
        var data = Data()
        
        data.append(version.littleEndianData)
        
        data.append(CompactSizeModel(value: UInt64(inputs.count)).encode())
        inputs.forEach { data.append($0.encode()) }
        
        data.append(CompactSizeModel(value: UInt64(outputs.count)).encode())
        for output in outputs {
            data.append(try output.encode())
        }
        
        data.append(lockTime.littleEndianData)
        
        return data
    }
}
