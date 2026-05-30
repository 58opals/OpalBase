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
        
        let failure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.BlockHeaderReader.makeSnapshot(
                height: 1,
                headerHexadecimal: "aa"
            )
        }
        
        #expect(failure.reason == .decoding)
        #expect(failure.message == "Invalid block header length: expected 80 bytes, got 1")
    }

    @Test("block header snapshots reject prefixed header hex")
    func rejectPrefixedBlockHeaderHexInSnapshots() throws {
        let headerHexadecimal = Data(repeating: 0x01, count: 80).hexadecimalString

        let failure = try Self.captureNetworkError {
            _ = try OpalBase.Network.Fulcrum.BlockHeaderReader.makeSnapshot(
                height: 1,
                headerHexadecimal: "0x\(headerHexadecimal)"
            )
        }

        #expect(failure.reason == .decoding)
        #expect(failure.message == "Cannot decode block header: 0x\(headerHexadecimal)")
    }
    
    private enum NetworkErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    private static func captureNetworkError(_ work: () throws -> Void) throws -> OpalBase.Network.Error {
        do {
            try work()
        } catch let failure as OpalBase.Network.Error {
            return failure
        } catch {
            throw NetworkErrorCaptureFailure.unexpected(error)
        }
        throw NetworkErrorCaptureFailure.didNotThrow
    }
}
