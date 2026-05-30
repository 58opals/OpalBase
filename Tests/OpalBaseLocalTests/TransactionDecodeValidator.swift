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

    @Test("encode rejects transactions without inputs or outputs")
    func transactionEncodeRejectsEmptyInputOrOutputVectors() {
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(value: 546, lockingScript: Data([0x51]))

        let noInputs = OpalBase.Transaction(version: 2, inputs: [], outputs: [output], lockTime: 0)
        let noOutputs = OpalBase.Transaction(version: 2, inputs: [input], outputs: [], lockTime: 0)

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            try noInputs.encode()
        }
        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            try noOutputs.encode()
        }
    }

    @Test("encode rejects outputs above maximum supply")
    func rejectOutputValuesAboveMaximumSupplyDuringTransactionEncode() {
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(
            value: OpalBase.Satoshi.maximumSatoshi + 1,
            lockingScript: Data([0x51])
        )
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [input],
            outputs: [output],
            lockTime: 0
        )

        #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
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

    @Test("decode rejects non-minimal CompactSize counts")
    func transactionDecodeRejectsNonMinimalCompactSizeCounts() {
        var malformed = Data()
        malformed.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version
        malformed.append(contentsOf: [0xfd, 0x00, 0x00]) // non-minimal input count 0
        malformed.append(0x00) // output count
        malformed.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // lock time

        #expect(throws: CompactSize.Error.self) {
            _ = try OpalBase.Transaction.decode(from: malformed)
        }
    }

    @Test("decode rejects transactions without inputs or outputs")
    func transactionDecodeRejectsEmptyInputOrOutputVectors() {
        var noInputs = Data()
        noInputs.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version
        noInputs.append(0x00) // input count
        noInputs.append(0x01) // output count
        noInputs.append(Data(repeating: 0x00, count: 8)) // output value
        noInputs.append(0x01) // locking bytecode length
        noInputs.append(0x51) // locking bytecode
        noInputs.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // lock time

        var noOutputs = Data()
        noOutputs.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version
        noOutputs.append(0x01) // input count
        noOutputs.append(Data(repeating: 0x00, count: 32)) // previous tx hash
        noOutputs.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // output index
        noOutputs.append(0x00) // unlocking script length
        noOutputs.append(contentsOf: [0xff, 0xff, 0xff, 0xff]) // sequence
        noOutputs.append(0x00) // output count
        noOutputs.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // lock time

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.decode(from: noInputs)
        }
        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.decode(from: noOutputs)
        }
    }
    
    @Test("decode rejects oversized output locking bytecode lengths")
    func transactionDecodeRejectsOversizedOutputLength() throws {
        var malformed = Data()
        malformed.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version
        malformed.append(0x01) // input count
        malformed.append(Data(repeating: 0x00, count: 32)) // previous tx hash
        malformed.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // output index
        malformed.append(0x00) // unlocking script length
        malformed.append(contentsOf: [0xff, 0xff, 0xff, 0xff]) // sequence
        malformed.append(0x01) // output count
        malformed.append(Data(repeating: 0x00, count: 8)) // output value
        malformed.append(0xff) // CompactSize uint64 prefix
        malformed.append(Data(repeating: 0xff, count: 8)) // UInt64.max length
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try OpalBase.Transaction.decode(from: malformed)
        }
    }

    @Test("decode rejects outputs above maximum supply")
    func rejectOutputValuesAboveMaximumSupplyDuringTransactionDecode() {
        let malformed = Self.makeSingleOutputTransactionData(
            outputValue: OpalBase.Satoshi.maximumSatoshi + 1
        )

        #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try OpalBase.Transaction.decode(from: malformed)
        }
    }

    @Test(
        "decode accepts valid output value boundaries",
        arguments: [UInt64(0), UInt64(546), OpalBase.Satoshi.maximumSatoshi]
    )
    func acceptValidOutputValueBoundariesDuringTransactionDecode(outputValue: UInt64) throws {
        let encoded = Self.makeSingleOutputTransactionData(outputValue: outputValue)

        let (transaction, bytesRead) = try OpalBase.Transaction.decode(from: encoded)
        let output = try #require(transaction.outputs.first)

        #expect(bytesRead == encoded.count)
        #expect(output.value == outputValue)
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

    @Test("block encode and decode reject empty transaction lists")
    func blockEncodeAndDecodeRejectEmptyTransactionLists() throws {
        let header = OpalBase.Block.Header(version: 2,
                                  previousBlockHash: Data(repeating: 0xaa, count: 32),
                                  merkleRoot: Data(repeating: 0xbb, count: 32),
                                  time: 1,
                                  bits: 2,
                                  nonce: 3)
        let block = OpalBase.Block(header: header, transactions: [])
        let encodedEmptyBlock = header.encode() + Data([0x00])

        #expect(throws: OpalBase.Block.Error.emptyTransactionList) {
            try block.encode()
        }
        #expect(throws: OpalBase.Block.Error.emptyTransactionList) {
            _ = try OpalBase.Block.decode(from: encodedEmptyBlock)
        }
    }

    @Test("block encode rejects malformed header hash lengths")
    func blockEncodeRejectsMalformedHeaderHashLengths() throws {
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

        let shortPreviousHashHeader = OpalBase.Block.Header(version: 2,
                                  previousBlockHash: Data(repeating: 0xaa, count: 31),
                                  merkleRoot: Data(repeating: 0xbb, count: 32),
                                  time: 1,
                                  bits: 2,
                                  nonce: 3)
        let shortMerkleRootHeader = OpalBase.Block.Header(version: 2,
                                  previousBlockHash: Data(repeating: 0xaa, count: 32),
                                  merkleRoot: Data(repeating: 0xbb, count: 31),
                                  time: 1,
                                  bits: 2,
                                  nonce: 3)

        #expect(throws: OpalBase.Block.Error.invalidPreviousBlockHashLength(expected: 32, actual: 31)) {
            try OpalBase.Block(header: shortPreviousHashHeader, transactions: [transaction]).encode()
        }
        #expect(throws: OpalBase.Block.Error.invalidMerkleRootLength(expected: 32, actual: 31)) {
            try OpalBase.Block(header: shortMerkleRootHeader, transactions: [transaction]).encode()
        }
    }
}

private extension TransactionDecodeValidator {
    static func makeSingleOutputTransactionData(outputValue: UInt64) -> Data {
        var encoded = Data()
        encoded.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version
        encoded.append(0x01) // input count
        encoded.append(Data(repeating: 0x00, count: 32)) // previous tx hash
        encoded.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // output index
        encoded.append(0x00) // unlocking script length
        encoded.append(contentsOf: [0xff, 0xff, 0xff, 0xff]) // sequence
        encoded.append(0x01) // output count
        encoded.append(outputValue.littleEndianData)
        encoded.append(0x00) // locking bytecode length
        encoded.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // lock time
        return encoded
    }
}
