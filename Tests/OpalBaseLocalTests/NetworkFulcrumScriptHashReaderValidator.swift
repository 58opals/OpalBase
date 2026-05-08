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
        
        let failure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.ScriptHashReader.validateScriptHash("dd")
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid script hash length: expected 32 bytes, got 1")
    }
    
    private static func captureNetworkError(_ work: () throws -> Void) -> OpalBase.Network.Error {
        do {
            try work()
            Issue.record("Expected OpalBase.Network.Error")
            return .init(reason: .unknown)
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch {
            Issue.record("Unexpected error: \(error)")
            return .init(reason: .unknown, message: String(describing: error))
        }
    }
}
