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
}
