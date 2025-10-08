import Foundation
import Testing
@testable import OpalBase

@Suite("Transaction Decoding", .tags(.unit, .transaction))
struct TransactionDecodingSuite {
    @Test("fails gracefully when input hash is truncated")
    func inputDecodingGuardsAgainstTruncatedHash() throws {
        var payload = Data()
        payload.append(Data(repeating: 0, count: 31))
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try Transaction.Input.decode(from: payload)
        }
    }
    
    @Test("fails gracefully when input script is truncated")
    func inputDecodingGuardsAgainstTruncatedScript() throws {
        var payload = Data()
        payload.append(Data(repeating: 0, count: 32))
        payload.append(UInt32(0).littleEndianData)
        payload.append(CompactSize(value: 5).encode())
        payload.append(Data([0x01]))
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try Transaction.Input.decode(from: payload)
        }
    }
    
    @Test("fails gracefully when output script is truncated")
    func outputDecodingGuardsAgainstTruncatedScript() throws {
        var payload = Data()
        payload.append(UInt64(1).littleEndianData)
        payload.append(CompactSize(value: 5).encode())
        payload.append(Data([0x01]))
        
        #expect(throws: Data.Error.indexOutOfRange) {
            _ = try Transaction.Output.decode(from: payload)
        }
    }
    
    @Test("decodes a valid transaction payload - v1")
    func transactionDecodingSucceedsWithValidPayload1() throws {
        let version: UInt32 = 2
        let previousTransactionHashData = Data((0..<32).map(UInt8.init))
        let previousTransactionIndex: UInt32 = 1
        let unlockingScript = Data([0x6a, 0x76])
        let sequence: UInt32 = 0xFFFF_FFFE
        
        let outputValue: UInt64 = 50_000_000
        let lockingScript = Data([0x76, 0xa9, 0x14, 0x88, 0xac])
        let lockTime: UInt32 = 0
        
        var payload = Data()
        payload.append(version.littleEndianData)
        
        payload.append(CompactSize(value: 1).encode())
        payload.append(previousTransactionHashData)
        payload.append(previousTransactionIndex.littleEndianData)
        payload.append(CompactSize(value: UInt64(unlockingScript.count)).encode())
        payload.append(unlockingScript)
        payload.append(sequence.littleEndianData)
        
        payload.append(CompactSize(value: 1).encode())
        payload.append(outputValue.littleEndianData)
        payload.append(CompactSize(value: UInt64(lockingScript.count)).encode())
        payload.append(lockingScript)
        
        payload.append(lockTime.littleEndianData)
        
        let (transaction, bytesRead) = try Transaction.decode(from: payload)
        
        #expect(bytesRead == payload.count)
        #expect(transaction.version == version)
        #expect(transaction.lockTime == lockTime)
        #expect(transaction.inputs.count == 1)
        #expect(transaction.outputs.count == 1)
        
        let input = try #require(transaction.inputs.first)
        #expect(input.previousTransactionHash.naturalOrder == previousTransactionHashData)
        #expect(input.previousTransactionOutputIndex == previousTransactionIndex)
        #expect(input.unlockingScript == unlockingScript)
        #expect(input.sequence == sequence)
        
        let output = try #require(transaction.outputs.first)
        #expect(output.value == outputValue)
        #expect(output.lockingScript == lockingScript)
    }
    
    @Test("decodes a valid transaction payload - v2")
    func transactionDecodingSucceedsWithValidPayload2() throws {
        let version: UInt32 = 2
        let lockTime: UInt32 = 0
        
        let previousTransactionHash = Data(repeating: 0x11, count: 32)
        let previousTransactionOutputIndex: UInt32 = 1
        let unlockingScript = Data([0x51])
        let sequence: UInt32 = 0xFFFFFFFE
        
        let outputValue: UInt64 = 50_000
        let lockingScript = Data([0x76, 0xa9, 0x14])
        
        var payload = Data()
        payload.append(version.littleEndianData)
        payload.append(CompactSize(value: 1).encode())
        payload.append(previousTransactionHash)
        payload.append(previousTransactionOutputIndex.littleEndianData)
        payload.append(CompactSize(value: UInt64(unlockingScript.count)).encode())
        payload.append(unlockingScript)
        payload.append(sequence.littleEndianData)
        payload.append(CompactSize(value: 1).encode())
        payload.append(outputValue.littleEndianData)
        payload.append(CompactSize(value: UInt64(lockingScript.count)).encode())
        payload.append(lockingScript)
        payload.append(lockTime.littleEndianData)
        
        let (transaction, bytesRead) = try Transaction.decode(from: payload)
        
        #expect(bytesRead == payload.count)
        #expect(transaction.version == version)
        #expect(transaction.lockTime == lockTime)
        #expect(transaction.inputs.count == 1)
        #expect(transaction.outputs.count == 1)
        
        let decodedInput = try #require(transaction.inputs.first)
        #expect(decodedInput.previousTransactionHash.naturalOrder == previousTransactionHash)
        #expect(decodedInput.previousTransactionOutputIndex == previousTransactionOutputIndex)
        #expect(decodedInput.unlockingScript == unlockingScript)
        #expect(decodedInput.sequence == sequence)
        
        let decodedOutput = try #require(transaction.outputs.first)
        #expect(decodedOutput.value == outputValue)
        #expect(decodedOutput.lockingScript == lockingScript)
    }
    
    @Test("decodes a valid transaction payload - v3")
    func transactionDecodingSucceedsForValidPayload() throws {
        let version: UInt32 = 2
        let previousTransactionHash = Data((0..<32).map(UInt8.init))
        let previousTransactionOutputIndex: UInt32 = 1
        let unlockingScript = Data([0x51, 0x21, 0x02])
        let sequence: UInt32 = 0xFFFFFFFE
        
        let outputValue: UInt64 = 12_345
        let lockingScript = Data([0x76, 0xA9, 0x14, 0x88, 0xAC])
        let lockTime: UInt32 = 500
        
        var payload = Data()
        payload.append(version.littleEndianData)
        payload.append(CompactSize(value: 1).encode())
        payload.append(previousTransactionHash)
        payload.append(previousTransactionOutputIndex.littleEndianData)
        payload.append(CompactSize(value: UInt64(unlockingScript.count)).encode())
        payload.append(unlockingScript)
        payload.append(sequence.littleEndianData)
        payload.append(CompactSize(value: 1).encode())
        payload.append(outputValue.littleEndianData)
        payload.append(CompactSize(value: UInt64(lockingScript.count)).encode())
        payload.append(lockingScript)
        payload.append(lockTime.littleEndianData)
        
        let (transaction, bytesRead) = try Transaction.decode(from: payload)
        
        #expect(bytesRead == payload.count)
        #expect(transaction.version == version)
        #expect(transaction.lockTime == lockTime)
        #expect(transaction.inputs.count == 1)
        #expect(transaction.outputs.count == 1)
        
        let decodedInput = transaction.inputs.first
        #expect(decodedInput?.previousTransactionHash.naturalOrder == previousTransactionHash)
        #expect(decodedInput?.previousTransactionOutputIndex == previousTransactionOutputIndex)
        #expect(decodedInput?.unlockingScript == unlockingScript)
        #expect(decodedInput?.sequence == sequence)
        
        let decodedOutput = transaction.outputs.first
        #expect(decodedOutput?.value == outputValue)
        #expect(decodedOutput?.lockingScript == lockingScript)
    }
    
    @Test("successfully decodes a well-formed transaction")
    func transactionDecodingSucceedsWithCompletePayload() throws {
        let version: UInt32 = 2
        let previousTransactionHash = Data(repeating: 0xAB, count: 32)
        let previousTransactionIndex: UInt32 = 1
        let unlockingScript = Data([0x51])
        let sequence: UInt32 = 0xFFFFFFFE
        let outputValue: UInt64 = 5_000
        let lockingScript = Data([0xAC])
        let lockTime: UInt32 = 0
        
        var payload = Data()
        payload.append(version.littleEndianData)
        payload.append(CompactSize(value: 1).encode())
        payload.append(previousTransactionHash)
        payload.append(previousTransactionIndex.littleEndianData)
        payload.append(CompactSize(value: UInt64(unlockingScript.count)).encode())
        payload.append(unlockingScript)
        payload.append(sequence.littleEndianData)
        payload.append(CompactSize(value: 1).encode())
        payload.append(outputValue.littleEndianData)
        payload.append(CompactSize(value: UInt64(lockingScript.count)).encode())
        payload.append(lockingScript)
        payload.append(lockTime.littleEndianData)
        
        let (transaction, bytesRead) = try Transaction.decode(from: payload)
        
        #expect(bytesRead == payload.count)
        #expect(transaction.version == version)
        #expect(transaction.lockTime == lockTime)
        #expect(transaction.inputs.count == 1)
        #expect(transaction.outputs.count == 1)
        
        let input = try #require(transaction.inputs.first)
        #expect(input.previousTransactionHash.naturalOrder == previousTransactionHash)
        #expect(input.previousTransactionOutputIndex == previousTransactionIndex)
        #expect(input.unlockingScript == unlockingScript)
        #expect(input.sequence == sequence)
        
        let output = try #require(transaction.outputs.first)
        #expect(output.value == outputValue)
        #expect(output.lockingScript == lockingScript)
    }
}
