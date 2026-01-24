import Foundation
import Testing
@testable import OpalBase

@Suite("Transaction hash type unspent transaction outputs", .tags(.unit))
struct TransactionHashTypeUnspentTransactionOutputsTests {
    @Test("hash type validation rejects unspent outputs with anyone-can-pay")
    func testHashTypeValidationRejectsUnspentOutputsWithAnyoneCanPay() throws {
        let hashType = Transaction.HashType.makeAll(anyoneCanPay: true,
                                                    includesUnspentTransactionOutputs: true)
        
        #expect(throws: Transaction.Error.unsupportedHashType) {
            try hashType.validate()
        }
    }
    
    @Test("hash type includes unspent outputs flag")
    func testHashTypeIncludesUnspentOutputsFlag() {
        let hashType = Transaction.HashType.makeAll(includesUnspentTransactionOutputs: true)
        
        #expect((hashType.value & 0x20) == 0x20)
    }
    
    @Test("hash preimage includes hash of unspent outputs in input order")
    func testPreimageIncludesUnspentTransactionOutputsHash() throws {
        let lockingScript = try makeLockingScript()
        let transaction = makeTransaction(lockingScript: lockingScript)
        let spentOutputs = [
            Transaction.Output(value: 9_000, lockingScript: lockingScript),
            Transaction.Output(value: 12_000, lockingScript: lockingScript)
        ]
        let hashType = Transaction.HashType.makeAll(includesUnspentTransactionOutputs: true)
        let preimage = try transaction.generatePreimage(for: 0,
                                                        hashType: hashType,
                                                        outputBeingSpent: spentOutputs[0],
                                                        spentOutputs: spentOutputs)
        let expectedHash = try makeUnspentTransactionOutputsHash(from: spentOutputs)
        let hashStartIndex = MemoryLayout<UInt32>.size + 32
        let hashEndIndex = hashStartIndex + 32
        let actualHash = preimage.subdata(in: hashStartIndex..<hashEndIndex)
        
        #expect(actualHash == expectedHash)
    }
    
    @Test("hash preimage requires unspent outputs when enabled")
    func testPreimageRequiresUnspentTransactionOutputsWhenEnabled() throws {
        let lockingScript = try makeLockingScript()
        let transaction = makeTransaction(lockingScript: lockingScript)
        let spentOutput = Transaction.Output(value: 9_000, lockingScript: lockingScript)
        let hashType = Transaction.HashType.makeAll(includesUnspentTransactionOutputs: true)
        
        #expect(throws: Transaction.Error.missingUnspentTransactionOutputs) {
            _ = try transaction.generatePreimage(for: 0,
                                                 hashType: hashType,
                                                 outputBeingSpent: spentOutput,
                                                 spentOutputs: nil)
        }
    }
    
    private func makeTransaction(lockingScript: Data) -> Transaction {
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let inputs = [
            Transaction.Input(previousTransactionHash: previousTransactionHash,
                              previousTransactionOutputIndex: 0,
                              unlockingScript: Data(),
                              sequence: 0xffffffff),
            Transaction.Input(previousTransactionHash: previousTransactionHash,
                              previousTransactionOutputIndex: 1,
                              unlockingScript: Data(),
                              sequence: 0xffffffff)
        ]
        let output = Transaction.Output(value: 7_000, lockingScript: lockingScript)
        return Transaction(version: 2, inputs: inputs, outputs: [output], lockTime: 0)
    }
    
    private func makeLockingScript() throws -> Data {
        let lockingScriptHexadecimal = "76a914" + String(repeating: "22", count: 20) + "88ac"
        return try Data(hexadecimalString: lockingScriptHexadecimal)
    }
    
    private func makeUnspentTransactionOutputsHash(from outputs: [Transaction.Output]) throws -> Data {
        var data = Data()
        for output in outputs {
            data.append(try output.encode())
        }
        return HASH256.hash(data)
    }
}
