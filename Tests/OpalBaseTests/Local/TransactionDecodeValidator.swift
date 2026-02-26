import Foundation
import Testing
@testable import OpalBase

@Suite("TransactionModel decoding", .tags(.unit))
struct TransactionDecodeValidator {
    @Test("decode reports consumed length for sliced data")
    func transactionDecodeBytesReadMatchesSliceLength() throws {
        let previousHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 1, count: 32))
        let input = TransactionModel.InputModel(previousTransactionHash: previousHash,
                                      previousTransactionOutputIndex: 1,
                                      unlockingScript: Data([0x51]))
        let output = TransactionModel.OutputModel(value: 546,
                                        lockingScript: Data([0x76, 0xa9, 0x14]) + Data(repeating: 0x00, count: 20))
        let transaction = TransactionModel(version: 2,
                                      inputs: [input],
                                      outputs: [output],
                                      lockTime: 0)
        
        let encoded = try transaction.encode()
        let padded = Data([0x00, 0x00]) + encoded
        let slice = padded[2...]
        
        let (decoded, bytesRead) = try TransactionModel.decode(from: slice)
        
        #expect(decoded.version == transaction.version)
        #expect(decoded.inputs.count == transaction.inputs.count)
        #expect(decoded.outputs.count == transaction.outputs.count)
        #expect(bytesRead == encoded.count)
    }
    
    @Test("decode fails when bytes are missing")
    func transactionDecodeThrowsForTruncatedPayload() throws {
        let previousHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 3, count: 32))
        let input = TransactionModel.InputModel(previousTransactionHash: previousHash,
                                      previousTransactionOutputIndex: 2,
                                      unlockingScript: Data([0x51]))
        let output = TransactionModel.OutputModel(value: 1_000,
                                        lockingScript: Data([0x51]))
        let transaction = TransactionModel(version: 1,
                                      inputs: [input],
                                      outputs: [output],
                                      lockTime: 0)
        
        let encoded = try transaction.encode()
        let truncated = encoded.dropLast()
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try TransactionModel.decode(from: Data(truncated))
        }
    }
    
    @Test("decode rejects truncated transaction payloads")
    func transactionDecodeRejectsTruncatedPayload() throws {
        let previousHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 1, count: 32))
        let input = TransactionModel.InputModel(previousTransactionHash: previousHash,
                                      previousTransactionOutputIndex: 1,
                                      unlockingScript: Data([0x51]))
        let output = TransactionModel.OutputModel(value: 546,
                                        lockingScript: Data([0x76, 0xa9, 0x14]) + Data(repeating: 0x00, count: 20))
        let transaction = TransactionModel(version: 2,
                                      inputs: [input],
                                      outputs: [output],
                                      lockTime: 0)
        
        let encoded = try transaction.encode()
        let truncated = Data(encoded.dropLast())
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try TransactionModel.decode(from: truncated)
        }
    }
    
    @Test("block decoding returns relative byte count")
    func blockDecodeBytesReadMatchesSliceLength() throws {
        let header = BlockModel.HeaderModel(version: 2,
                                  previousBlockHash: Data(repeating: 0xaa, count: 32),
                                  merkleRoot: Data(repeating: 0xbb, count: 32),
                                  time: 1,
                                  bits: 2,
                                  nonce: 3)
        let previousHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 2, count: 32))
        let input = TransactionModel.InputModel(previousTransactionHash: previousHash,
                                      previousTransactionOutputIndex: 0,
                                      unlockingScript: Data([0x51]))
        let output = TransactionModel.OutputModel(value: 600,
                                        lockingScript: Data([0x51]))
        let transaction = TransactionModel(version: 1,
                                      inputs: [input],
                                      outputs: [output],
                                      lockTime: 0)
        let block = BlockModel(header: header, transactions: [transaction])
        
        let encoded = try block.encode()
        let padded = Data([0xff, 0xee, 0xdd]) + encoded
        let slice = padded[3...]
        
        let (decoded, bytesRead) = try BlockModel.decode(from: slice)
        
        #expect(decoded.header.version == header.version)
        #expect(decoded.transactions.count == block.transactions.count)
        #expect(bytesRead == encoded.count)
    }
}
