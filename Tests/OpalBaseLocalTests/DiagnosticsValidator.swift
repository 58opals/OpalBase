// DiagnosticsValidator.swift

import Foundation
import OpalDiagnostics
import Testing
import OpalBaseTestSupport
import SwiftFulcrum
@testable import OpalBase

@Suite("OpalBase diagnostics", .tags(.unit, .wallet))
struct DiagnosticsValidator {
    @Test("Fulcrum diagnostics follow OpalDiagnostics configuration", .timeLimit(.minutes(1)))
    func fulcrumDiagnosticsFollowOpalDiagnosticsConfiguration() async {
        let configuredRecords = await failedFulcrumStartupBridgeRecords(configuration: diagnosticsConfiguration())
        #expect(configuredRecords.contains {
            $0.event == OpalDiagnostics.Event.networkFulcrumClientFailed
        })

        let defaultRecords = await failedFulcrumStartupBridgeRecords(configuration: .init())
        #expect(defaultRecords.isEmpty)
    }

    private func failedFulcrumStartupBridgeRecords(
        configuration: OpalDiagnostics.Configuration
    ) async -> [OpalDiagnostics.Record] {
        await OpalDiagnostics.withConfiguration(configuration) {
            let networkConfiguration = OpalBase.Network.Configuration(
                serverURLs: [URL(string: "ws://127.0.0.1:1")!],
                serverCatalog: .init(mainnetServers: [], chipnetServers: [], testnetServers: []),
                connectTimeout: .milliseconds(50),
                reconnect: .init(
                    maximumAttempts: 1,
                    initialDelay: .milliseconds(1),
                    maximumDelay: .milliseconds(1),
                    jitterMultiplierRange: 1.0 ... 1.0
                )
            )

            do {
                _ = try await OpalBase.Network.Fulcrum.Client(
                    configuration: networkConfiguration
                )
                Issue.record("Expected Fulcrum client startup to fail against a closed local port.")
            } catch {
                // Expected: the local closed port gives the client a deterministic startup failure.
            }

            return OpalDiagnostics.recentRecords.filter(isOpalBaseNetworkBridgeRecord)
        }
    }

    private func isOpalBaseNetworkBridgeRecord(_ record: OpalDiagnostics.Record) -> Bool {
        guard record.category == OpalDiagnostics.Category.network else { return false }
        return [
            OpalDiagnostics.Event.networkFulcrumClientStarted,
            OpalDiagnostics.Event.networkFulcrumClientFailed
        ].contains(record.event)
    }

    func diagnosticsConfiguration(
        minimumLevel: OpalDiagnostics.Level = .debug,
        categoryFilter: OpalDiagnostics.CategoryFilter = .all
    ) -> OpalDiagnostics.Configuration {
        OpalDiagnostics.Configuration(
            minimumLevel: minimumLevel,
            categoryFilter: categoryFilter,
            bufferPolicy: .enabled(capacity: 512)
        )
    }

    func errorCodes(in records: [OpalDiagnostics.Record]) -> Set<OpalDiagnostics.ErrorCode> {
        Set(
            records
                .flatMap(\.fields)
                .filter { $0.name == OpalDiagnostics.Field.Name.errorCode }
                .map { OpalDiagnostics.ErrorCode(rawValue: $0.value) }
        )
    }

    func recordsContain(
        _ records: [OpalDiagnostics.Record],
        event: OpalDiagnostics.Event,
        errorCode: OpalDiagnostics.ErrorCode
    ) -> Bool {
        records.contains { record in
            record.event == event && recordContains(record, errorCode: errorCode)
        }
    }

    func recordContains(
        _ record: OpalDiagnostics.Record,
        errorCode: OpalDiagnostics.ErrorCode
    ) -> Bool {
        record.fields.contains {
            $0.name == OpalDiagnostics.Field.Name.errorCode &&
                $0.value == errorCode.rawValue
        }
    }

    func render(_ records: [OpalDiagnostics.Record]) -> String {
        records.map { record in
            let fields = record.fields.map { "\($0.name)=\($0.value)" }.joined(separator: " ")
            return "\(record.category.rawValue) \(record.event.rawValue) \(fields)"
        }.joined(separator: "\n")
    }
}
