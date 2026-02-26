// TransactionModel+OutputModel.swift

import Foundation

extension TransactionModel {
    public struct OutputModel {
        public let value: UInt64
        public let lockingScript: Data
        public let tokenData: CashTokensModel.TokenData?
        
        var lockingScriptLength: CompactSizeModel {
            CompactSizeModel(value: UInt64(lockingScript.count))
        }
        
        /// Initializes a TransactionModel.OutputModel instance.
        /// - Parameters:
        ///   - value: The number of satoshi to be transferred.
        ///   - lockingScript: The contents of the locking script.
        ///   - tokenData: Token metadata to prefix before the locking script.
        public init(value: UInt64, lockingScript: Data, tokenData: CashTokensModel.TokenData? = nil) {
            self.value = value
            self.lockingScript = lockingScript
            self.tokenData = tokenData
        }
        
        /// Initializes a TransactionModel.OutputModel instance.
        /// - Parameters:
        ///   - value: The number of satoshi to be transferred.
        ///   - address: The address of the output's recipient.
        ///   - tokenData: Token metadata to prefix before the locking script.
        public init(value: UInt64, address: AddressModel, tokenData: CashTokensModel.TokenData? = nil) {
            self.value = value
            self.lockingScript = address.lockingScript.data
            self.tokenData = tokenData
        }
        
        /// Encodes the TransactionModel.OutputModel into Data.
        /// - Returns: The encoded data.
        public func encode() throws -> Data {
            var writer = Data.WriterModel()
            writer.writeLittleEndian(value)
            let tokenPrefixData = try makeTokenPrefixData()
            let tokenPrefixAndLockingBytecodeLength = CompactSizeModel(value: UInt64(tokenPrefixData.count + lockingScript.count))
            writer.writeCompactSize(tokenPrefixAndLockingBytecodeLength)
            writer.writeData(tokenPrefixData)
            writer.writeData(lockingScript)
            return writer.data
        }
        
        /// Decodes a TransactionModel.OutputModel instance from Data.
        /// - Parameter data: The data to decode from.
        /// - Throws: `CompactSizeModel.Error` if decoding fails.
        /// - Returns: A tuple containing the decoded TransactionModel.OutputModel and the number of bytes read.
        static func decode(from data: Data) throws -> (output: OutputModel, bytesRead: Int) {
            var reader = Data.ReaderModel(data)
            let output = try decode(from: &reader)
            return (output, reader.bytesRead)
        }
        
        static func decode(from reader: inout Data.ReaderModel) throws -> OutputModel {
            let value: UInt64 = try reader.readLittleEndian()
            let tokenPrefixAndLockingBytecodeLength = try reader.readCompactSize()
            let tokenPrefixAndLockingBytecode = try reader.readData(count: Int(tokenPrefixAndLockingBytecodeLength.value))
            if tokenPrefixAndLockingBytecode.first == CashTokensModel.TokenPrefixModel.prefixToken {
                let decoded = try CashTokensModel.TokenPrefixModel.decode(prefixPlusBytecode: tokenPrefixAndLockingBytecode)
                return OutputModel(value: value,
                              lockingScript: decoded.lockingBytecode,
                              tokenData: decoded.tokenData)
            }
            
            return OutputModel(value: value,
                          lockingScript: tokenPrefixAndLockingBytecode,
                          tokenData: nil)
        }
        
        func makeTokenPrefixData() throws -> Data {
            guard let tokenData else { return Data() }
            return try CashTokensModel.TokenPrefixModel.encode(tokenData: tokenData)
        }
        
        func calculateDustThreshold(feeRate: UInt64) throws -> UInt64 {
            let outputSize = try calculateSerializedSize()
            let spendingInputSize = 148
            let totalSize = outputSize + spendingInputSize
            let baseFee = try TransactionModel.makeFee(size: totalSize, feePerByte: feeRate)
            let (scaledFee, overflow) = baseFee.multipliedReportingOverflow(by: 3)
            return overflow ? UInt64.max : scaledFee
        }
        
        private func calculateSerializedSize() throws -> Int {
            let tokenPrefixData = try makeTokenPrefixData()
            let lockingBytecodeLength = tokenPrefixData.count + lockingScript.count
            let lengthPrefixSize = CompactSizeModel(value: UInt64(lockingBytecodeLength)).encodedSize
            return 8 + lengthPrefixSize + lockingBytecodeLength
        }
    }
}

extension TransactionModel.OutputModel: Sendable {}
extension TransactionModel.OutputModel: Equatable {}

extension TransactionModel.OutputModel: CustomStringConvertible {
    public var description: String {
        """
        TransactionModel OutputModel:
            Value: \(value)
            Locking ScriptModel: \(lockingScript.hexadecimalString)
        """
    }
}
