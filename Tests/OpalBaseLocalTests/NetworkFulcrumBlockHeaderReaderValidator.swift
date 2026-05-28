// NetworkFulcrumBlockHeaderReaderValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Fulcrum.BlockHeaderReader", .tags(.unit, .network))
struct NetworkFulcrumBlockHeaderReaderValidator {
    @Test("block header snapshots require exactly one encoded header")
    func blockHeaderSnapshotsRequireOneEncodedHeader() throws {
        let headerHexadecimal = Data(repeating: 0x01, count: 80).hexadecimalString
        let snapshot = try OpalBase.Network.Fulcrum.BlockHeaderReader.makeSnapshot(
            height: 1,
            headerHexadecimal: headerHexadecimal
        )
        
        #expect(snapshot.height == 1)
        #expect(snapshot.headerHexadecimal == headerHexadecimal)
        
        let failure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.BlockHeaderReader.makeSnapshot(
                height: 1,
                headerHexadecimal: "aa"
            )
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid block header length: expected 80 bytes, got 1")
    }

    @Test("block header snapshots reject prefixed header hex")
    func rejectPrefixedBlockHeaderHexInSnapshots() {
        let headerHexadecimal = Data(repeating: 0x01, count: 80).hexadecimalString

        let failure = Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.BlockHeaderReader.makeSnapshot(
                height: 1,
                headerHexadecimal: "0x\(headerHexadecimal)"
            )
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Cannot decode block header: 0x\(headerHexadecimal)")
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
