// DiagnosticsValidator~ClaimableOperations.swift

import Foundation
import OpalDiagnostics
import Testing
import OpalBaseTestSupport
import SwiftFulcrum
@testable import OpalBase

extension DiagnosticsValidator {
    @Test("claimable envelope network mismatches record failure diagnostics")
    func claimableEnvelopeNetworkMismatchesRecordFailureDiagnostics() throws {
        let records = try OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
            let encodedEnvelope = envelope.encode()

            #expect(
                throws: OpalBase.Claimable.Error.networkMismatch(expected: .mainnet, actual: .chipnet)
            ) {
                try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope, on: .mainnet)
            }

            return OpalDiagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.claimableEnvelopeDecodeFailed,
            errorCode: OpalDiagnostics.ErrorCode.claimableInvalidEnvelope
        ))
        #expect(records.contains {
            $0.event == OpalDiagnostics.Event.claimableEnvelopeDecodeSucceeded
        } == false)
    }

    @Test("claimable share code envelope data failures record diagnostics")
    func claimableShareCodeEnvelopeDataFailuresRecordDiagnostics() {
        let records = OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            #expect(throws: OpalBase.Claimable.Error.invalidShareCodeFormat) {
                _ = try OpalBase.Claimable.ShareCode.decodeEnvelopeData("not-a-share-code")
            }

            return OpalDiagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.claimableShareCodeDecodeFailed,
            errorCode: OpalDiagnostics.ErrorCode.claimableInvalidShareCode
        ))
    }

    @Test("claimable status failures use the status error code")
    func claimableStatusFailuresUseStatusErrorCode() async throws {
        let records = try await OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(network: .chipnet)
            let resolver = OpalBase.Claimable.StatusResolver(
                network: .chipnet,
                scriptHashReader: .init(
                    fetchHistory: { _, _ in throw OpalBase.Network.Error(reason: .timeout) },
                    fetchUnspent: { _, _ in [] }
                )
            )

            await #expect(throws: OpalBase.Network.Error.self) {
                _ = try await resolver.resolve(
                    for: envelope,
                    includeUnconfirmed: true,
                    currentBlockHeight: 499
                )
            }

            return OpalDiagnostics.recentRecords(category: OpalDiagnostics.Category.claimable)
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.claimableStatusResolveFailed,
            errorCode: OpalDiagnostics.ErrorCode.claimableStatusFailed
        ))
    }
}
