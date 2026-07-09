// TransactionDecodeValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Transaction decoding", .tags(.unit))
struct TransactionDecodeValidator {
    @Test("hash decoding rejects invalid byte counts")
    func hashDecodingRejectsInvalidByteCounts() {
        let malformedHash = Data(repeating: 0x01, count: OpalBase.Transaction.Hash.expectedByteCount - 1)
            .base64EncodedString()
        let payload = Data(#"{"originalData":"\#(malformedHash)"}"#.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(OpalBase.Transaction.Hash.self, from: payload)
        }
    }

    @Test("hash encoding rejects invalid byte counts")
    func hashEncodingRejectsInvalidByteCounts() {
        let malformedHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x01, count: OpalBase.Transaction.Hash.expectedByteCount - 1)
        )

        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(malformedHash)
        }
    }

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

    @Test("encode rejects transactions without inputs or outputs", arguments: EmptyTransactionVectorCase.allCases)
    fileprivate func transactionEncodeRejectsEmptyInputOrOutputVectors(_ emptyVectorCase: EmptyTransactionVectorCase) {
        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            try emptyVectorCase.makeTransaction().encode()
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

    @Test("encode rejects output totals above maximum supply")
    func rejectOutputValueTotalsAboveMaximumSupplyDuringTransactionEncode() {
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [input],
            outputs: [
                OpalBase.Transaction.Output(
                    value: OpalBase.Satoshi.maximumSatoshi,
                    lockingScript: Data([0x51])
                ),
                OpalBase.Transaction.Output(value: 1, lockingScript: Data([0x51]))
            ],
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

    @Test(
        "decode rejects impossible vector counts before allocation",
        arguments: ImpossibleTransactionVectorCountCase.allCases
    )
    fileprivate func transactionDecodeRejectsImpossibleVectorCountsBeforeAllocation(
        _ vectorCase: ImpossibleTransactionVectorCountCase
    ) {
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try OpalBase.Transaction.decode(from: vectorCase.makeEncodedTransactionData())
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

    @Test("decode rejects transactions without inputs or outputs", arguments: EmptyTransactionVectorCase.allCases)
    fileprivate func transactionDecodeRejectsEmptyInputOrOutputVectors(_ emptyVectorCase: EmptyTransactionVectorCase) {
        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.decode(from: emptyVectorCase.makeEncodedTransactionData())
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

    @Test("decode rejects output totals above maximum supply")
    func rejectOutputValueTotalsAboveMaximumSupplyDuringTransactionDecode() {
        let malformed = Self.makeTransactionData(outputValues: [
            OpalBase.Satoshi.maximumSatoshi,
            1
        ])

        #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try OpalBase.Transaction.decode(from: malformed)
        }
    }

    @Test(
        "decode accepts valid output value boundaries",
        arguments: ValidOutputValueBoundaryCase.allCases
    )
    fileprivate func acceptValidOutputValueBoundariesDuringTransactionDecode(
        _ boundaryCase: ValidOutputValueBoundaryCase
    ) throws {
        let encoded = Self.makeSingleOutputTransactionData(outputValue: boundaryCase.outputValue)

        let (transaction, bytesRead) = try OpalBase.Transaction.decode(from: encoded)
        let output = try #require(transaction.outputs.first)

        #expect(bytesRead == encoded.count)
        #expect(output.value == boundaryCase.outputValue)
    }

    @Test("encode and decode accept output totals at maximum supply")
    func acceptOutputValueTotalsAtMaximumSupply() throws {
        let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let outputValues = [
            OpalBase.Satoshi.maximumSatoshi - 1,
            UInt64(1)
        ]
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [input],
            outputs: outputValues.map { OpalBase.Transaction.Output(value: $0, lockingScript: Data([0x51])) },
            lockTime: 0
        )

        let encoded = try transaction.encode()
        let (decoded, bytesRead) = try OpalBase.Transaction.decode(from: encoded)

        #expect(bytesRead == encoded.count)
        #expect(decoded.outputs.map(\.value) == outputValues)
    }
    
    @Test("block decoding returns relative byte count")
    func blockDecodeBytesReadMatchesSliceLength() throws {
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
        let merkleRoot = try OpalBase.Block.computeMerkleRoot(for: [transaction])
        let header = OpalBase.Block.Header(version: 2,
                                  previousBlockHash: Data(repeating: 0xaa, count: 32),
                                  merkleRoot: merkleRoot,
                                  time: 1,
                                  bits: 2,
                                  nonce: 3)
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

    @Test("block decode rejects impossible transaction counts before allocation")
    func blockDecodeRejectsImpossibleTransactionCountsBeforeAllocation() {
        let header = OpalBase.Block.Header(
            version: 2,
            previousBlockHash: Data(repeating: 0xaa, count: 32),
            merkleRoot: Data(repeating: 0xbb, count: 32),
            time: 1,
            bits: 2,
            nonce: 3
        )
        let encodedBlock = header.encode() + CompactSize(value: UInt64(Int.max)).encode()

        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try OpalBase.Block.decode(from: encodedBlock)
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

    @Test("block encode and decode reject merkle root mismatches")
    func blockEncodeAndDecodeRejectMerkleRootMismatches() throws {
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
        let computedMerkleRoot = try OpalBase.Block.computeMerkleRoot(for: [transaction])
        let mismatchedMerkleRoot = Data(repeating: 0xbb, count: 32)
        let header = OpalBase.Block.Header(version: 2,
                                  previousBlockHash: Data(repeating: 0xaa, count: 32),
                                  merkleRoot: mismatchedMerkleRoot,
                                  time: 1,
                                  bits: 2,
                                  nonce: 3)

        #expect(throws: OpalBase.Block.Error.merkleRootMismatch(
            computed: computedMerkleRoot,
            header: mismatchedMerkleRoot
        )) {
            try OpalBase.Block(header: header, transactions: [transaction]).encode()
        }

        let encodedBlock = try header.encode() + Data([0x01]) + transaction.encode()
        #expect(throws: OpalBase.Block.Error.merkleRootMismatch(
            computed: computedMerkleRoot,
            header: mismatchedMerkleRoot
        )) {
            _ = try OpalBase.Block.decode(from: encodedBlock)
        }
    }

    @Test("block merkle root duplicates the last hash for odd transaction counts")
    func blockMerkleRootDuplicatesLastHashForOddTransactionCounts() throws {
        let transactions = (0..<3).map { index in
            let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: UInt8(index + 1), count: 32))
            let input = OpalBase.Transaction.Input(previousTransactionHash: previousHash,
                                          previousTransactionOutputIndex: 0,
                                          unlockingScript: Data([0x51]))
            let output = OpalBase.Transaction.Output(value: UInt64(600 + index),
                                            lockingScript: Data([0x51]))
            return OpalBase.Transaction(version: 1,
                                  inputs: [input],
                                  outputs: [output],
                                  lockTime: 0)
        }
        let transactionHashes = try transactions.map { transaction in
            OpalCryptoAdapter.hash256(try transaction.encode())
        }
        let leftBranch = OpalCryptoAdapter.hash256(transactionHashes[0] + transactionHashes[1])
        let rightBranch = OpalCryptoAdapter.hash256(transactionHashes[2] + transactionHashes[2])
        let expectedMerkleRoot = OpalCryptoAdapter.hash256(leftBranch + rightBranch)

        #expect(try OpalBase.Block.computeMerkleRoot(for: transactions) == expectedMerkleRoot)
    }

    enum EmptyTransactionVectorCase: CaseIterable, CustomStringConvertible, Sendable {
        case inputs
        case outputs

        var description: String {
            switch self {
            case .inputs:
                "inputs"
            case .outputs:
                "outputs"
            }
        }

        func makeTransaction() -> OpalBase.Transaction {
            let previousHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32))
            let input = OpalBase.Transaction.Input(
                previousTransactionHash: previousHash,
                previousTransactionOutputIndex: 0,
                unlockingScript: Data()
            )
            let output = OpalBase.Transaction.Output(value: 546, lockingScript: Data([0x51]))

            switch self {
            case .inputs:
                return OpalBase.Transaction(version: 2, inputs: [], outputs: [output], lockTime: 0)
            case .outputs:
                return OpalBase.Transaction(version: 2, inputs: [input], outputs: [], lockTime: 0)
            }
        }

        func makeEncodedTransactionData() -> Data {
            var encoded = Data()
            encoded.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version

            switch self {
            case .inputs:
                encoded.append(0x00) // input count
                encoded.append(0x01) // output count
                encoded.append(Data(repeating: 0x00, count: 8)) // output value
                encoded.append(0x01) // locking bytecode length
                encoded.append(0x51) // locking bytecode
            case .outputs:
                encoded.append(0x01) // input count
                encoded.append(Data(repeating: 0x00, count: 32)) // previous tx hash
                encoded.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // output index
                encoded.append(0x00) // unlocking script length
                encoded.append(contentsOf: [0xff, 0xff, 0xff, 0xff]) // sequence
                encoded.append(0x00) // output count
            }

            encoded.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // lock time
            return encoded
        }
    }

    enum ImpossibleTransactionVectorCountCase: CaseIterable, CustomStringConvertible, Sendable {
        case inputs
        case outputs

        var description: String {
            switch self {
            case .inputs:
                "inputs"
            case .outputs:
                "outputs"
            }
        }

        func makeEncodedTransactionData() -> Data {
            var encoded = Data()
            encoded.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version

            switch self {
            case .inputs:
                encoded.append(CompactSize(value: UInt64(Int.max)).encode())
            case .outputs:
                encoded.append(0x01) // input count
                encoded.append(Data(repeating: 0x00, count: 32)) // previous tx hash
                encoded.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // output index
                encoded.append(0x00) // unlocking script length
                encoded.append(contentsOf: [0xff, 0xff, 0xff, 0xff]) // sequence
                encoded.append(CompactSize(value: UInt64(Int.max)).encode())
            }

            return encoded
        }
    }

    enum ValidOutputValueBoundaryCase: CaseIterable, CustomStringConvertible, Sendable {
        case zero
        case dust
        case maximumSupply

        var description: String {
            switch self {
            case .zero:
                "zero"
            case .dust:
                "dust"
            case .maximumSupply:
                "maximum supply"
            }
        }

        var outputValue: UInt64 {
            switch self {
            case .zero:
                return 0
            case .dust:
                return 546
            case .maximumSupply:
                return OpalBase.Satoshi.maximumSatoshi
            }
        }
    }
}

private extension TransactionDecodeValidator {
    static func makeSingleOutputTransactionData(outputValue: UInt64) -> Data {
        makeTransactionData(outputValues: [outputValue])
    }

    static func makeTransactionData(outputValues: [UInt64]) -> Data {
        var encoded = Data()
        encoded.append(contentsOf: [0x01, 0x00, 0x00, 0x00]) // version
        encoded.append(0x01) // input count
        encoded.append(Data(repeating: 0x00, count: 32)) // previous tx hash
        encoded.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // output index
        encoded.append(0x00) // unlocking script length
        encoded.append(contentsOf: [0xff, 0xff, 0xff, 0xff]) // sequence
        encoded.append(UInt8(outputValues.count)) // output count
        for outputValue in outputValues {
            encoded.append(outputValue.littleEndianData)
            encoded.append(0x00) // locking bytecode length
        }
        encoded.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // lock time
        return encoded
    }
}
