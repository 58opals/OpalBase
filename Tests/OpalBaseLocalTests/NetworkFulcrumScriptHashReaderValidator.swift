// NetworkFulcrumScriptHashReaderValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.ScriptHashReader", .tags(.unit, .network))
struct NetworkFulcrumScriptHashReaderValidator {
    @Test("script hash requests require valid hashes")
    func scriptHashRequestsRequireValidHashes() throws {
        let scriptHash = String(repeating: "d", count: 64)
        
        #expect(try OpalBase.Network.Fulcrum.ScriptHashReader.validateScriptHash(scriptHash) == scriptHash)
        
        let failure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.ScriptHashReader.validateScriptHash("dd")
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid script hash length: expected 32 bytes, got 1")
    }

    @Test("unspent outputs require matching script hashes")
    func unspentOutputRequiresMatchingScriptHash() throws {
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(value: 546, lockingScript: Data([0x51]))
        let transaction = OpalBase.Transaction(version: 2, inputs: [input], outputs: [output], lockTime: 0)
        let rawTransactionData = try transaction.encode()
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
        )
        let requestedScriptHash = OpalCryptoAdapter.sha256(Data([0x52])).reversedData.hexadecimalString

        let failure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.ScriptHashReader.makeUnspentOutput(
                transactionHash: transactionHash,
                transactionIdentifier: transactionHash.reverseOrder.hexadecimalString,
                transactionPosition: 0,
                rawTransactionData: rawTransactionData,
                scriptHashHex: requestedScriptHash
            )
        }

        #expect(failure.reason == .protocolViolation)
        #expect(failure.message == "Unspent transaction output script hash mismatch")
    }
    
    enum NetworkErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    private static func captureNetworkError(_ work: () throws -> Void) throws -> OpalBase.Network.Error {
        do {
            try work()
            throw NetworkErrorCaptureFailure.didNotThrow
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch let failure as NetworkErrorCaptureFailure {
            throw failure
        } catch {
            throw NetworkErrorCaptureFailure.unexpected(error)
        }
    }
}
