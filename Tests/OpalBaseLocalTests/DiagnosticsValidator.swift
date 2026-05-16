// DiagnosticsValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Diagnostics", .tags(.unit, .wallet))
struct DiagnosticsValidator {
    @Test("public diagnostics catalog exposes stable names")
    func publicDiagnosticsCatalogExposesStableNames() {
        #expect(Set(OpalBase.Diagnostics.Categories.all) == [
            OpalBase.Diagnostics.Categories.wallet,
            OpalBase.Diagnostics.Categories.account,
            OpalBase.Diagnostics.Categories.addressBook,
            OpalBase.Diagnostics.Categories.network,
            OpalBase.Diagnostics.Categories.cashFusion,
            OpalBase.Diagnostics.Categories.hedge,
            OpalBase.Diagnostics.Categories.transaction,
            OpalBase.Diagnostics.Categories.claimable,
            OpalBase.Diagnostics.Categories.tokenMetadata,
            OpalBase.Diagnostics.Categories.storage
        ])

        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.walletCreateStarted))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.addressReserveSucceeded))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.utxoRefreshFailed))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.spendPrepareStarted))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.cashFusionSessionFinalized))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.hedgeFundingBroadcastFailed))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.claimableShareCodeDecodeFailed))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.tokenMetadataSyncSucceeded))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.networkDiagnosticsSnapshotRecorded))

        #expect(OpalBase.Diagnostics.Fields.errorCode == "error_code")
        #expect(OpalBase.Diagnostics.Fields.accountIndex == "account_index")
        #expect(OpalBase.Diagnostics.Fields.accountCount == "account_count")
        #expect(OpalBase.Diagnostics.Fields.tokenMetadataCount == "token_metadata_count")
        #expect(OpalBase.Diagnostics.Fields.all.contains(OpalBase.Diagnostics.Fields.errorType))

        #expect(OpalBase.Diagnostics.ErrorCodes.walletAccountAlreadyExists == "wallet.account_already_exists")
        #expect(OpalBase.Diagnostics.ErrorCodes.walletAccountNotFound == "wallet.account_not_found")
        #expect(OpalBase.Diagnostics.ErrorCodes.claimableInvalidShareCode == "claimable.invalid_share_code")
        #expect(OpalBase.Diagnostics.ErrorCodes.hedgeFundingFailed == "hedge.funding_failed")
        #expect(OpalBase.Diagnostics.ErrorCodes.all.contains(OpalBase.Diagnostics.ErrorCodes.cashFusionReservationFailed))
    }

    @Test("recent record filtering respects categories and trace identifiers")
    func recentRecordFilteringRespectsCategoriesAndTraceIdentifiers() async throws {
        let traceID = OpalBase.Diagnostics.TraceID()
        let result = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            try await OpalBase.Diagnostics.withTraceID(traceID) {
                let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
                try await wallet.addAccount(unhardenedIndex: 0)
            }

            return (
                records: OpalBase.Diagnostics.recentRecords,
                filteredWalletRecords: OpalBase.Diagnostics.recentRecords(
                    category: OpalBase.Diagnostics.Categories.wallet,
                    traceID: traceID
                )
            )
        }

        let walletRecords = result.records.filter { $0.category == OpalBase.Diagnostics.Categories.wallet }
        let accountRecords = result.records.filter { $0.category == OpalBase.Diagnostics.Categories.account }

        #expect(walletRecords.isEmpty == false)
        #expect(accountRecords.isEmpty == false)
        #expect(Set(result.filteredWalletRecords.map(\.category)) == [OpalBase.Diagnostics.Categories.wallet])
        #expect(result.filteredWalletRecords.allSatisfy { $0.traceID == traceID })
    }

    @Test("category filters retain only enabled categories")
    func categoryFiltersRetainOnlyEnabledCategories() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration(categoryFilter: .enabled([OpalBase.Diagnostics.Categories.wallet]))
        ) {
            let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
            try await wallet.addAccount(unhardenedIndex: 0)
            return OpalBase.Diagnostics.recentRecords
        }

        #expect(records.isEmpty == false)
        #expect(records.allSatisfy { $0.category == OpalBase.Diagnostics.Categories.wallet })
        #expect(records.contains { $0.event == OpalBase.Diagnostics.Events.walletAccountCreateSucceeded })
    }

    @Test("wallet operations propagate trace IDs into lower diagnostics")
    func walletOperationsPropagateTraceIDsIntoLowerDiagnostics() async throws {
        let traceID = OpalBase.Diagnostics.TraceID()
        let records = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            try await OpalBase.Diagnostics.withTraceID(traceID) {
                let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
                try await wallet.addAccount(unhardenedIndex: 0)
                _ = try await wallet.fetchAccount(at: 0)
            }

            return OpalBase.Diagnostics.recentRecords.filter { $0.traceID == traceID }
        }

        #expect(records.contains { $0.event == OpalBase.Diagnostics.Events.walletCreateStarted })
        #expect(records.contains { $0.event == OpalBase.Diagnostics.Events.walletAccountCreateSucceeded })
        #expect(records.contains { $0.event == OpalBase.Diagnostics.Events.walletAccountFetchSucceeded })
        #expect(records.contains { $0.event.rawValue.hasPrefix("opalcrypto.") })
        #expect(records.allSatisfy { $0.traceID == traceID })
    }

    @Test("recent diagnostics redact sensitive values and use safe field names")
    func recentDiagnosticsRedactSensitiveValuesAndUseSafeFieldNames() async throws {
        let mnemonic = try AccountTestFixtures.makeMnemonic()
        let result = try await OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            let wallet = try OpalBase.Wallet(mnemonic: mnemonic)
            try await wallet.addAccount(unhardenedIndex: 0)
            let account = try await wallet.fetchAccount(at: 0)
            let entry = try await account.reserveNextReceivingDerivedAddress()
            let fullAddress = entry.address.generateString(withPrefix: true)
            let sensitiveValues = [
                AccountTestFixtures.mnemonicWords.joined(separator: " "),
                try mnemonic.deriveSeed().rawRepresentation.hexadecimalString,
                "private key 000102030405060708090a0b0c0d0e0f",
                "L1aW4aubDFB7yfras2S1mN3bqg9w7L3w5h8QYV4AExampleWIF",
                fullAddress,
                "0100000001abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                #"{"contract":"raw","oracle":"message","redeemScript":"51"}"#,
                "oracle message payload",
                "oracle signature payload",
                "redeem script payload",
                "raw proof material payload"
            ]

            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.walletCreateStarted,
                category: OpalBase.Diagnostics.Categories.wallet,
                fields: sensitiveValues.enumerated().map { index, value in
                    OpalBaseDiagnostics.privateField("private_payload_\(index)", value)
                }
            )

            return (records: OpalBase.Diagnostics.recentRecords, sensitiveValues: sensitiveValues)
        }

        let renderedRecords = render(result.records)
        for sensitiveValue in result.sensitiveValues {
            #expect(renderedRecords.contains(sensitiveValue) == false)
        }

        let fieldNames = OpalBase.Diagnostics.Fields.all.joined(separator: " ")
        for forbiddenNameFragment in [
            "mnemonic", "seed", "private_key", "wif", "full_address", "raw_transaction",
            "contract_json", "oracle_message", "oracle_signature", "redeem_script", "raw_proof"
        ] {
            #expect(fieldNames.contains(forbiddenNameFragment) == false)
        }
    }

    @Test("error code fields remain stable")
    func errorCodeFieldsRemainStable() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
            try await wallet.addAccount(unhardenedIndex: 0)

            await #expect(throws: OpalBase.Wallet.Error.accountAlreadyExists(index: 0)) {
                try await wallet.addAccount(unhardenedIndex: 0)
            }
            await #expect(throws: OpalBase.Wallet.Error.cannotFetchAccount(index: 9)) {
                _ = try await wallet.fetchAccount(at: 9)
            }
            #expect(throws: OpalBase.Claimable.Error.invalidShareCodeFormat) {
                _ = try OpalBase.Claimable.ShareCode.decode("not-a-share-code")
            }

            return OpalBase.Diagnostics.recentRecords
        }

        #expect(errorCodes(in: records).contains(OpalBase.Diagnostics.ErrorCodes.walletAccountAlreadyExists))
        #expect(errorCodes(in: records).contains(OpalBase.Diagnostics.ErrorCodes.walletAccountNotFound))
        #expect(errorCodes(in: records).contains(OpalBase.Diagnostics.ErrorCodes.claimableInvalidShareCode))
    }

    @Test("legacy network logger and metrics remain compatible")
    func legacyNetworkLoggerAndMetricsRemainCompatible() async {
        let capture = LegacyNetworkLogCapture()
        let logger = OpalBase.Network.Logger { level, message, metadata, file, function, line in
            capture.append(
                level: level,
                message: message,
                metadata: metadata,
                file: file,
                function: function,
                line: line
            )
        }

        logger.log(
            .info,
            "legacy-network-message",
            metadata: ["component": "fulcrum"],
            file: "DiagnosticsValidator.swift",
            function: "legacyNetworkLoggerAndMetricsRemainCompatible",
            line: 1
        )

        let legacyEntries = capture.entries()
        #expect(legacyEntries.count == 1)
        #expect(legacyEntries.first?.level == .info)
        #expect(legacyEntries.first?.message == "legacy-network-message")
        #expect(legacyEntries.first?.metadata?["component"] == "fulcrum")

        let records = await OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            let metrics = OpalBase.Network.Metrics()
            await metrics.recordDiagnosticsSnapshot(
                url: URL(string: "wss://fulcrum.example.com:50004")!,
                snapshot: .init(
                    reconnectionAttemptCount: 2,
                    reconnectSuccesses: 1,
                    inflightUnaryCallCount: 3,
                    activeSubscriptionCount: 4
                )
            )
            return OpalBase.Diagnostics.recentRecords
        }

        #expect(records.contains { record in
            record.category == OpalBase.Diagnostics.Categories.network &&
                record.event == OpalBase.Diagnostics.Events.networkDiagnosticsSnapshotRecorded
        })
    }
}

private func diagnosticsConfiguration(
    categoryFilter: OpalBase.Diagnostics.CategoryFilter = .all
) -> OpalBase.Diagnostics.Configuration {
    OpalBase.Diagnostics.Configuration(
        minimumLevel: .debug,
        categoryFilter: categoryFilter,
        bufferPolicy: .enabled(capacity: 512)
    )
}

private func errorCodes(in records: [OpalBase.Diagnostics.Record]) -> Set<String> {
    Set(
        records
            .flatMap(\.fields)
            .filter { $0.name == OpalBase.Diagnostics.Fields.errorCode }
            .map(\.value)
    )
}

private func render(_ records: [OpalBase.Diagnostics.Record]) -> String {
    records.map { record in
        let fields = record.fields.map { "\($0.name)=\($0.value)" }.joined(separator: " ")
        return "\(record.category.rawValue) \(record.event.rawValue) \(fields)"
    }.joined(separator: "\n")
}

private final class LegacyNetworkLogCapture: @unchecked Sendable {
    struct Entry {
        let level: OpalBase.Network.LogLevel
        let message: String
        let metadata: [String: String]?
        let file: String
        let function: String
        let line: UInt
    }

    private let lock = NSLock()
    private var recordedEntries: [Entry] = []

    func append(
        level: OpalBase.Network.LogLevel,
        message: String,
        metadata: [String: String]?,
        file: String,
        function: String,
        line: UInt
    ) {
        lock.withLock {
            recordedEntries.append(
                .init(
                    level: level,
                    message: message,
                    metadata: metadata,
                    file: file,
                    function: function,
                    line: line
                )
            )
        }
    }

    func entries() -> [Entry] {
        lock.withLock { recordedEntries }
    }
}
