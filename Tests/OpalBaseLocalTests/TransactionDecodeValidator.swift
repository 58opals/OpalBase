// TransactionDecodeValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Transaction decoding", .tags(.unit))
struct TransactionDecodeValidator {
    @Test("encode rejects invalid previous transaction hash length")
    func transactionEncodeRejectsInvalidPreviousTransactionHashLength() throws {
        let invalidHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 31))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: invalidHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(value: 546, lockingScript: Data([0x51]))
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [input],
            outputs: [output],
            lockTime: 0
        )

        #expect(
            throws: OpalBase.Transaction.Error.invalidTransactionHashLength(
                expected: 32,
                actual: 31
            )
        ) {
            try transaction.encode()
        }
    }

    @Test("decode reports consumed length for sliced data")
    func transactionDecodeBytesReadMatchesSliceLength() throws {
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 1, count: 32))
        let input = OpalBase.Transaction.Input(previousTransactionHash: previousHash,
                                      previousTransactionOutputIndex: 1,
                                      unlockingScript: Data([0x51]))
        let output = OpalBase.Transaction.Output(value: 546,
                                        lockingScript: Data([0x76, 0xa9, 0x14]) + Data(repeating: 0x00, count: 20))
        let transaction = OpalBase.Transaction(version: 2,
                                      inputs: [input],
                                      outputs: [output],
                                      lockTime: 0)
        
        let encoded = try transaction.encode()
        let padded = Data([0x00, 0x00]) + encoded
        let slice = padded[2...]
        
        let (decoded, bytesRead) = try OpalBase.Transaction.decode(from: slice)
        
        #expect(decoded.version == transaction.version)
        #expect(decoded.inputs.count == transaction.inputs.count)
        #expect(decoded.outputs.count == transaction.outputs.count)
        #expect(bytesRead == encoded.count)
    }
    
    @Test("decode fails when bytes are missing")
    func transactionDecodeThrowsForTruncatedPayload() throws {
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 3, count: 32))
        let input = OpalBase.Transaction.Input(previousTransactionHash: previousHash,
                                      previousTransactionOutputIndex: 2,
                                      unlockingScript: Data([0x51]))
        let output = OpalBase.Transaction.Output(value: 1_000,
                                        lockingScript: Data([0x51]))
        let transaction = OpalBase.Transaction(version: 1,
                                      inputs: [input],
                                      outputs: [output],
                                      lockTime: 0)
        
        let encoded = try transaction.encode()
        let truncated = encoded.dropLast()
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try OpalBase.Transaction.decode(from: Data(truncated))
        }
    }
    
    @Test("decode rejects truncated transaction payloads")
    func transactionDecodeRejectsTruncatedPayload() throws {
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 1, count: 32))
        let input = OpalBase.Transaction.Input(previousTransactionHash: previousHash,
                                      previousTransactionOutputIndex: 1,
                                      unlockingScript: Data([0x51]))
        let output = OpalBase.Transaction.Output(value: 546,
                                        lockingScript: Data([0x76, 0xa9, 0x14]) + Data(repeating: 0x00, count: 20))
        let transaction = OpalBase.Transaction(version: 2,
                                      inputs: [input],
                                      outputs: [output],
                                      lockTime: 0)
        
        let encoded = try transaction.encode()
        let truncated = Data(encoded.dropLast())
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try OpalBase.Transaction.decode(from: truncated)
        }
    }
    
    @Test("decode rejects oversized unlocking script lengths")
    func transactionDecodeRejectsOversizedUnlockingScriptLength() throws {
        var malformed = Data()
        malformed.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version
        malformed.append(0x01) // input count
        malformed.append(Data(repeating: 0x00, count: 32)) // previous tx hash
        malformed.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // output index
        malformed.append(0xff) // CompactSize uint64 prefix
        malformed.append(Data(repeating: 0xff, count: 8)) // UInt64.max length
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try OpalBase.Transaction.decode(from: malformed)
        }
    }
    
    @Test("decode rejects oversized output locking bytecode lengths")
    func transactionDecodeRejectsOversizedOutputLength() throws {
        var malformed = Data()
        malformed.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version
        malformed.append(0x00) // input count
        malformed.append(0x01) // output count
        malformed.append(Data(repeating: 0x00, count: 8)) // output value
        malformed.append(0xff) // CompactSize uint64 prefix
        malformed.append(Data(repeating: 0xff, count: 8)) // UInt64.max length
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try OpalBase.Transaction.decode(from: malformed)
        }
    }
    
    @Test("block decoding returns relative byte count")
    func blockDecodeBytesReadMatchesSliceLength() throws {
        let header = OpalBase.Block.Header(version: 2,
                                  previousBlockHash: Data(repeating: 0xaa, count: 32),
                                  merkleRoot: Data(repeating: 0xbb, count: 32),
                                  time: 1,
                                  bits: 2,
                                  nonce: 3)
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 2, count: 32))
        let input = OpalBase.Transaction.Input(previousTransactionHash: previousHash,
                                      previousTransactionOutputIndex: 0,
                                      unlockingScript: Data([0x51]))
        let output = OpalBase.Transaction.Output(value: 600,
                                        lockingScript: Data([0x51]))
        let transaction = OpalBase.Transaction(version: 1,
                                      inputs: [input],
                                      outputs: [output],
                                      lockTime: 0)
        let block = OpalBase.Block(header: header, transactions: [transaction])
        
        let encoded = try block.encode()
        let padded = Data([0xff, 0xee, 0xdd]) + encoded
        let slice = padded[3...]
        
        let (decoded, bytesRead) = try OpalBase.Block.decode(from: slice)
        
        #expect(decoded.header.version == header.version)
        #expect(decoded.transactions.count == block.transactions.count)
        #expect(bytesRead == encoded.count)
    }
}
