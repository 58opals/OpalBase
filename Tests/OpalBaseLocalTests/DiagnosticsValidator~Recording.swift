// DiagnosticsValidator~Recording.swift

import Foundation
import OpalDiagnostics
import Testing
import OpalBaseTestSupport
import SwiftFulcrum
@testable import OpalBase

extension DiagnosticsValidator {
    @Test("recent record filtering respects categories and trace identifiers")
    func recentRecordFilteringRespectsCategoriesAndTraceIdentifiers() async throws {
        let traceID = OpalDiagnostics.TraceID()
        let result = try await OpalDiagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            try await OpalDiagnostics.withTraceID(traceID) {
                let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
                try await wallet.addAccount(unhardenedIndex: 0)
            }

            return (
                records: OpalDiagnostics.recentRecords,
                filteredWalletRecords: OpalDiagnostics.recentRecords(
                    category: OpalDiagnostics.Category.wallet,
                    traceID: traceID
                )
            )
        }

        let walletRecords = result.records.filter { $0.category == OpalDiagnostics.Category.wallet }
        let accountRecords = result.records.filter { $0.category == OpalDiagnostics.Category.account }

        #expect(walletRecords.isEmpty == false)
        #expect(accountRecords.isEmpty == false)
        #expect(Set(result.filteredWalletRecords.map(\.category)) == [OpalDiagnostics.Category.wallet])
        #expect(result.filteredWalletRecords.allSatisfy { $0.traceID == traceID })
    }

    @Test("category filters retain only enabled categories")
    func categoryFiltersRetainOnlyEnabledCategories() async throws {
        let records = try await OpalDiagnostics.withConfiguration(
            diagnosticsConfiguration(categoryFilter: .enabled([OpalDiagnostics.Category.wallet]))
        ) {
            let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
            try await wallet.addAccount(unhardenedIndex: 0)
            return OpalDiagnostics.recentRecords
        }

        #expect(records.isEmpty == false)
        #expect(records.allSatisfy { $0.category == OpalDiagnostics.Category.wallet })
        #expect(records.contains { $0.event == OpalDiagnostics.Event.walletAccountCreateSucceeded })
    }

    @Test("default diagnostic levels classify routine and outcome events")
    func defaultDiagnosticLevelsClassifyRoutineAndOutcomeEvents() {
        let records = OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            recordLevelFixtureDiagnostics()
            return OpalDiagnostics.recentRecords(category: OpalDiagnostics.Category.wallet) +
                OpalDiagnostics.recentRecords(category: OpalDiagnostics.Category.cashFusion)
        }

        #expect(records.first {
            $0.event == OpalDiagnostics.Event.walletCreateStarted
        }?.level == .debug)
        #expect(records.first {
            $0.event == OpalDiagnostics.Event.walletCreateSucceeded
        }?.level == .debug)
        #expect(records.first {
            $0.event == OpalDiagnostics.Event.walletCreateFailed
        }?.level == .error)
        #expect(records.first {
            $0.event == OpalDiagnostics.Event.cashFusionSessionFinalized
        }?.level == .notice)

        let noticeRecords = OpalDiagnostics.withConfiguration(
            diagnosticsConfiguration(minimumLevel: .notice)
        ) {
            recordLevelFixtureDiagnostics()
            return OpalDiagnostics.recentRecords
        }
        let visibleEvents = Set(noticeRecords.map { $0.event })

        #expect(!visibleEvents.contains(OpalDiagnostics.Event.walletCreateStarted))
        #expect(!visibleEvents.contains(OpalDiagnostics.Event.walletCreateSucceeded))
        #expect(visibleEvents.contains(OpalDiagnostics.Event.walletCreateFailed))
        #expect(visibleEvents.contains(OpalDiagnostics.Event.cashFusionSessionFinalized))
    }

    @Test("network diagnostic events record through OpalDiagnostics")
    func networkDiagnosticEventsRecordThroughOpalDiagnostics() {
        let records = OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            OpalDiagnostics.record(
                OpalDiagnostics.Event.networkDiagnosticsCountersRecorded,
                category: OpalDiagnostics.Category.network,
                fields: [
                    OpalDiagnostics.Field.operation("record_network_diagnostics_snapshot"),
                    OpalDiagnostics.Field.module(),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.reconnectionAttemptCount, 2),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.reconnectSuccessCount, 1),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.inflightUnaryCallCount, 3),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.activeSubscriptionCount, 4)
                ]
            )
            OpalDiagnostics.record(
                OpalDiagnostics.Event.networkDiagnosticsRegistryUpdateRecorded,
                category: OpalDiagnostics.Category.network,
                fields: [
                    OpalDiagnostics.Field.operation("record_network_diagnostics_subscriptions"),
                    OpalDiagnostics.Field.module(),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.activeSubscriptionCount, 1)
                ]
            )
            return OpalDiagnostics.recentRecords
        }

        #expect(records.contains { record in
            record.category == OpalDiagnostics.Category.network &&
                record.event == OpalDiagnostics.Event.networkDiagnosticsCountersRecorded
        })
        #expect(records.contains { record in
            record.category == OpalDiagnostics.Category.network &&
                record.event == OpalDiagnostics.Event.networkDiagnosticsRegistryUpdateRecorded &&
                record.fields.contains {
                    $0.name == OpalDiagnostics.Field.Name.activeSubscriptionCount &&
                        $0.value == "1"
                }
        })
    }

    private func recordLevelFixtureDiagnostics() {
        OpalDiagnostics.record(
            OpalDiagnostics.Event.walletCreateStarted,
            category: OpalDiagnostics.Category.wallet
        )
        OpalDiagnostics.record(
            OpalDiagnostics.Event.walletCreateSucceeded,
            category: OpalDiagnostics.Category.wallet
        )
        OpalDiagnostics.record(
            OpalDiagnostics.Event.walletCreateFailed,
            category: OpalDiagnostics.Category.wallet
        )
        OpalDiagnostics.record(
            OpalDiagnostics.Event.cashFusionSessionFinalized,
            category: OpalDiagnostics.Category.cashFusion
        )
    }
}
