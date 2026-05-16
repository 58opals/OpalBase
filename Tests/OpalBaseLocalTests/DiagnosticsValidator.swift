// DiagnosticsValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
import SwiftFulcrum
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
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.hedgeParticipantMaterialReserveStarted))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.hedgeFundingBroadcastFailed))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.claimableShareCodeDecodeFailed))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.tokenMetadataSyncSucceeded))
        #expect(OpalBase.Diagnostics.Events.all.contains(OpalBase.Diagnostics.Events.networkDiagnosticsSnapshotRecorded))

        #expect(OpalBase.Diagnostics.Fields.errorCode == "error_code")
        #expect(OpalBase.Diagnostics.Fields.accountIndex == "account_index")
        #expect(OpalBase.Diagnostics.Fields.accountCount == "account_count")
        #expect(OpalBase.Diagnostics.Fields.tokenMetadataCount == "token_metadata_count")
        #expect(OpalBase.Diagnostics.Fields.all.contains(OpalBase.Diagnostics.Fields.reconnectionAttemptCount))
        #expect(OpalBase.Diagnostics.Fields.all.contains(OpalBase.Diagnostics.Fields.activeSubscriptionCount))
        #expect(OpalBase.Diagnostics.Fields.all.contains(OpalBase.Diagnostics.Fields.errorType))

        let stableErrorCodes = [
            OpalBase.Diagnostics.ErrorCodes.walletAccountAlreadyExists: "wallet.account_already_exists",
            OpalBase.Diagnostics.ErrorCodes.walletAccountNotFound: "wallet.account_not_found",
            OpalBase.Diagnostics.ErrorCodes.accountBalanceRefreshFailed: "account.balance_refresh_failed",
            OpalBase.Diagnostics.ErrorCodes.accountTransactionHistoryRefreshFailed: "account.transaction_history_refresh_failed",
            OpalBase.Diagnostics.ErrorCodes.claimableInvalidShareCode: "claimable.invalid_share_code",
            OpalBase.Diagnostics.ErrorCodes.hedgeFundingFailed: "hedge.funding_failed"
        ]
        for (actual, expected) in stableErrorCodes {
            #expect(actual == expected)
        }
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

    @Test("default diagnostic levels classify routine and outcome events")
    func defaultDiagnosticLevelsClassifyRoutineAndOutcomeEvents() {
        let records = OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            recordLevelFixtureDiagnostics()
            return OpalBase.Diagnostics.recentRecords(category: OpalBase.Diagnostics.Categories.wallet) +
                OpalBase.Diagnostics.recentRecords(category: OpalBase.Diagnostics.Categories.cashFusion)
        }

        #expect(records.first {
            $0.event == OpalBase.Diagnostics.Events.walletCreateStarted
        }?.level == .debug)
        #expect(records.first {
            $0.event == OpalBase.Diagnostics.Events.walletCreateSucceeded
        }?.level == .debug)
        #expect(records.first {
            $0.event == OpalBase.Diagnostics.Events.walletCreateFailed
        }?.level == .error)
        #expect(records.first {
            $0.event == OpalBase.Diagnostics.Events.cashFusionSessionFinalized
        }?.level == .notice)

        let noticeRecords = OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration(minimumLevel: .notice)
        ) {
            recordLevelFixtureDiagnostics()
            return OpalBase.Diagnostics.recentRecords
        }
        let visibleEvents = Set(noticeRecords.map { $0.event })

        #expect(!visibleEvents.contains(OpalBase.Diagnostics.Events.walletCreateStarted))
        #expect(!visibleEvents.contains(OpalBase.Diagnostics.Events.walletCreateSucceeded))
        #expect(visibleEvents.contains(OpalBase.Diagnostics.Events.walletCreateFailed))
        #expect(visibleEvents.contains(OpalBase.Diagnostics.Events.cashFusionSessionFinalized))
    }

    @Test("Fulcrum logging toggle suppresses OpalBase network diagnostics", .timeLimit(.minutes(1)))
    func fulcrumLoggingToggleSuppressesOpalBaseNetworkDiagnostics() async {
        let enabledRecords = await failedFulcrumStartupBridgeRecords(isLoggingEnabled: true)
        #expect(enabledRecords.contains {
            $0.event == OpalBase.Diagnostics.Events.networkFulcrumClientFailed
        })

        let disabledRecords = await failedFulcrumStartupBridgeRecords(isLoggingEnabled: false)
        #expect(disabledRecords.isEmpty)
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

    @Test("hedge participant reservation emits boundary diagnostics")
    func hedgeParticipantReservationEmitsBoundaryDiagnostics() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            let account = try await AccountTestFixtures.makeAccount()
            _ = try await account.reserveHedgeParticipantMaterial(network: .chipnet)

            return OpalBase.Diagnostics.recentRecords(
                category: OpalBase.Diagnostics.Categories.hedge
            )
        }

        #expect(records.contains {
            $0.event == OpalBase.Diagnostics.Events.hedgeParticipantMaterialReserveStarted
        })
        #expect(records.contains {
            $0.event == OpalBase.Diagnostics.Events.hedgeParticipantMaterialReserved
        })
    }

    @Test("hedge funding prepare failures use the hedge error code")
    func hedgeFundingPrepareFailuresUseHedgeErrorCode() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            let account = try await AccountTestFixtures.makeAccount()
            let request = try await makeDiagnosticsHedgeFundingRequest(for: account)

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await account.prepareHedgeFunding(request)
            }

            return OpalBase.Diagnostics.recentRecords(category: OpalBase.Diagnostics.Categories.hedge)
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.hedgeFundingPrepareFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.hedgeFundingFailed
        ))
    }

    @Test("hedge funding broadcast failures use the hedge error code")
    func hedgeFundingBroadcastFailuresUseHedgeErrorCode() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            let account = try await AccountTestFixtures.makeAccount()
            _ = try await AccountTestFixtures.addUnspentOutput(
                to: account,
                value: 6_000_000,
                hashByte: 0x53
            )
            let request = try await makeDiagnosticsHedgeFundingRequest(for: account)
            let plan = try await account.prepareHedgeFunding(request)
            let client = OpalBase.Network.TransactionClient(
                broadcastTransaction: { _ in throw NetworkStubError.forced("hedge-broadcast") },
                fetchConfirmations: { _ in nil },
                fetchConfirmationStatus: { transactionHash in
                    .init(
                        transactionHash: transactionHash,
                        transactionHeight: nil,
                        tipHeight: 0,
                        confirmations: nil
                    )
                }
            )

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await plan.buildAndBroadcast(via: client)
            }
            try await plan.cancelReservation()

            return OpalBase.Diagnostics.recentRecords(category: OpalBase.Diagnostics.Categories.hedge)
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.hedgeFundingBroadcastFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.hedgeFundingFailed
        ))
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

    @Test("SwiftFulcrum errors use stable network error codes")
    func swiftFulcrumErrorsUseStableNetworkErrorCodes() {
        #expect(OpalBaseDiagnostics.errorCode(
            for: SwiftFulcrum.Client.Error.client(.timeout(.seconds(3)))
        ) == OpalBase.Diagnostics.ErrorCodes.networkTimeout)
        #expect(OpalBaseDiagnostics.errorCode(
            for: SwiftFulcrum.Client.Error.transport(.heartbeatTimeout)
        ) == OpalBase.Diagnostics.ErrorCodes.networkTransport)
        #expect(OpalBaseDiagnostics.errorCode(
            for: SwiftFulcrum.Client.Error.coding(.decode(nil))
        ) == OpalBase.Diagnostics.ErrorCodes.networkDecoding)
    }

    @Test("balance refresh failures use a stable error code")
    func balanceRefreshFailuresUseStableErrorCode() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
            try await wallet.addAccount(unhardenedIndex: 0)

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await wallet.calculateBalance { _ in
                    throw NetworkStubError.forced("balance-refresh")
                }
            }

            return OpalBase.Diagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.walletBalanceRefreshFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.accountBalanceRefreshFailed
        ))
    }

    @Test("transaction history failures use a stable error code")
    func transactionHistoryFailuresUseStableErrorCode() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            let account = try await AccountTestFixtures.makeAccount()
            let reader = makeDiagnosticsAddressReader { _, _ in
                throw NetworkStubError.forced("history-refresh")
            }

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await account.refreshTransactionHistory(using: reader)
            }

            return OpalBase.Diagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.transactionHistoryRefreshFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.accountTransactionHistoryRefreshFailed
        ))
    }

    @Test("transaction detail refresh failures use a stable error code")
    func transactionDetailRefreshFailuresUseStableErrorCode() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            let account = try await AccountTestFixtures.makeAccount()
            let entry = try await account.reserveNextReceivingDerivedAddress()
            let historyEntry = AccountTestFixtures.makeHistoryEntry(hashByte: 0x52)
            let reader = makeDiagnosticsAddressReader { address, _ in
                address == entry.address.string ? [historyEntry] : []
            }
            let transactionReader = OpalBase.Network.TransactionReader { _ in
                throw NetworkStubError.forced("transaction-detail-refresh")
            }

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await account.refreshTransactionHistory(
                    using: reader,
                    transactionReader: transactionReader
                )
            }

            return OpalBase.Diagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.transactionHistoryRefreshFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.accountTransactionDetailsRefreshFailed
        ))
    }

    @Test("insufficient funds use the stable insufficient funds error code")
    func insufficientFundsUseStableInsufficientFundsErrorCode() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            let account = try await AccountTestFixtures.makeAccount()
            let recipientAddress = try await account.reserveNextReceivingAddress()
            let payment = OpalBase.Account.Payment(
                recipients: [
                    .init(address: recipientAddress, amount: try OpalBase.Satoshi(1_000))
                ]
            )

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await account.prepareSpend(payment)
            }

            return OpalBase.Diagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.spendPrepareFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.accountInsufficientFunds
        ))
    }

    @Test("empty confirmation refresh records diagnostics")
    func emptyConfirmationRefreshRecordsDiagnostics() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            let account = try await AccountTestFixtures.makeAccount()
            let client = OpalBase.Network.TransactionClient(
                broadcastTransaction: { _ in
                    throw OpalBase.Network.Error(reason: .protocolViolation)
                },
                fetchConfirmations: { _ in nil },
                fetchConfirmationStatus: { transactionHash in
                    .init(
                        transactionHash: transactionHash,
                        transactionHeight: nil,
                        tipHeight: 0,
                        confirmations: nil
                    )
                }
            )

            let changeSet = try await account.refreshTransactionConfirmations(using: client)
            #expect(changeSet.isEmpty)

            return OpalBase.Diagnostics.recentRecords
        }

        #expect(records.contains {
            $0.event == OpalBase.Diagnostics.Events.transactionConfirmationRefreshStarted
        })
        let succeededRecords = records.filter {
            $0.event == OpalBase.Diagnostics.Events.transactionConfirmationRefreshSucceeded
        }
        #expect(succeededRecords.contains { record in
            record.fields.contains {
                $0.name == OpalBase.Diagnostics.Fields.transactionCount &&
                    $0.value == "0"
            }
        })
    }

    @Test("claimable envelope network mismatches record failure diagnostics")
    func claimableEnvelopeNetworkMismatchesRecordFailureDiagnostics() throws {
        let records = try OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
            let encodedEnvelope = envelope.encode()

            #expect(
                throws: OpalBase.Claimable.Error.networkMismatch(expected: .mainnet, actual: .chipnet)
            ) {
                try OpalBase.Claimable.Envelope.decode(from: encodedEnvelope, on: .mainnet)
            }

            return OpalBase.Diagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.claimableEnvelopeDecodeFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.claimableInvalidEnvelope
        ))
        #expect(records.contains {
            $0.event == OpalBase.Diagnostics.Events.claimableEnvelopeDecodeSucceeded
        } == false)
    }

    @Test("claimable share code envelope data failures record diagnostics")
    func claimableShareCodeEnvelopeDataFailuresRecordDiagnostics() {
        let records = OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            #expect(throws: OpalBase.Claimable.Error.invalidShareCodeFormat) {
                _ = try OpalBase.Claimable.ShareCode.decodeEnvelopeData("not-a-share-code")
            }

            return OpalBase.Diagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.claimableShareCodeDecodeFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.claimableInvalidShareCode
        ))
    }

    @Test("claimable status failures use the status error code")
    func claimableStatusFailuresUseStatusErrorCode() async throws {
        let records = try await OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
            let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
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

            return OpalBase.Diagnostics.recentRecords(category: OpalBase.Diagnostics.Categories.claimable)
        }

        #expect(recordsContain(
            records,
            event: OpalBase.Diagnostics.Events.claimableStatusResolveFailed,
            errorCode: OpalBase.Diagnostics.ErrorCodes.claimableStatusFailed
        ))
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
            await metrics.recordSubscriptionRegistryUpdate(
                url: URL(string: "wss://fulcrum.example.com:50004")!,
                subscriptions: [
                    .init(methodPath: "blockchain.address.subscribe", identifier: "abc")
                ]
            )
            return OpalBase.Diagnostics.recentRecords
        }

        #expect(records.contains { record in
            record.category == OpalBase.Diagnostics.Categories.network &&
                record.event == OpalBase.Diagnostics.Events.networkDiagnosticsSnapshotRecorded
        })
        #expect(records.contains { record in
            record.category == OpalBase.Diagnostics.Categories.network &&
                record.event == OpalBase.Diagnostics.Events.networkDiagnosticsSubscriptionsRecorded &&
                record.fields.contains {
                    $0.name == OpalBase.Diagnostics.Fields.activeSubscriptionCount &&
                        $0.value == "1"
                }
        })
    }
}

private func diagnosticsConfiguration(
    minimumLevel: OpalBase.Diagnostics.Level = .debug,
    categoryFilter: OpalBase.Diagnostics.CategoryFilter = .all
) -> OpalBase.Diagnostics.Configuration {
    OpalBase.Diagnostics.Configuration(
        minimumLevel: minimumLevel,
        categoryFilter: categoryFilter,
        bufferPolicy: .enabled(capacity: 512)
    )
}

private func recordLevelFixtureDiagnostics() {
    OpalBaseDiagnostics.record(
        OpalBase.Diagnostics.Events.walletCreateStarted,
        category: OpalBase.Diagnostics.Categories.wallet
    )
    OpalBaseDiagnostics.record(
        OpalBase.Diagnostics.Events.walletCreateSucceeded,
        category: OpalBase.Diagnostics.Categories.wallet
    )
    OpalBaseDiagnostics.record(
        OpalBase.Diagnostics.Events.walletCreateFailed,
        category: OpalBase.Diagnostics.Categories.wallet
    )
    OpalBaseDiagnostics.record(
        OpalBase.Diagnostics.Events.cashFusionSessionFinalized,
        category: OpalBase.Diagnostics.Categories.cashFusion
    )
}

private func failedFulcrumStartupBridgeRecords(
    isLoggingEnabled: Bool
) async -> [OpalBase.Diagnostics.Record] {
    await OpalBase.Diagnostics.withConfiguration(diagnosticsConfiguration()) {
        let configuration = OpalBase.Network.Configuration(
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
                configuration: configuration,
                metrics: OpalBase.Network.Metrics(),
                isLoggingEnabled: isLoggingEnabled
            )
            Issue.record("Expected Fulcrum client startup to fail against a closed local port.")
        } catch {
            // Expected: the local closed port gives the client a deterministic startup failure.
        }

        return OpalBase.Diagnostics.recentRecords.filter(isOpalBaseNetworkBridgeRecord)
    }
}

private func isOpalBaseNetworkBridgeRecord(_ record: OpalBase.Diagnostics.Record) -> Bool {
    guard record.category == OpalBase.Diagnostics.Categories.network else { return false }
    return [
        OpalBase.Diagnostics.Events.networkFulcrumClientStarted,
        OpalBase.Diagnostics.Events.networkFulcrumClientFailed,
        OpalBase.Diagnostics.Events.networkDiagnosticsSnapshotRecorded,
        OpalBase.Diagnostics.Events.networkDiagnosticsSubscriptionsRecorded
    ].contains(record.event)
}

private func makeDiagnosticsHedgeFundingRequest(
    for account: OpalBase.Account
) async throws -> OpalBase.Hedge.USDThirtyDaySimpleHedgeRequest {
    let walletMaterial = try await account.reserveHedgeParticipantMaterial()
    return try HedgeFixtureData.betaRequest(walletParticipant: walletMaterial)
}

private func makeDiagnosticsAddressReader(
    fetchHistory: @escaping @Sendable (String, Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry]
) -> OpalBase.Network.AddressReader {
    OpalBase.Network.AddressReader(
        fetchBalance: { _, _ in .init(confirmed: 0, unconfirmed: 0) },
        fetchUnspentOutputs: { _, _ in [] },
        fetchHistory: fetchHistory,
        fetchFirstUse: { _ in nil },
        fetchMempoolTransactions: { _ in [] },
        fetchScriptHash: { address in address },
        subscribeToAddress: { _ in AsyncThrowingStream { $0.finish() } }
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

private func recordsContain(
    _ records: [OpalBase.Diagnostics.Record],
    event: OpalBase.Diagnostics.Event,
    errorCode: String
) -> Bool {
    records.contains { record in
        record.event == event && recordContains(record, errorCode: errorCode)
    }
}

private func recordContains(
    _ record: OpalBase.Diagnostics.Record,
    errorCode: String
) -> Bool {
    record.fields.contains {
        $0.name == OpalBase.Diagnostics.Fields.errorCode &&
            $0.value == errorCode
    }
}

private func render(_ records: [OpalBase.Diagnostics.Record]) -> String {
    records.map { record in
        let fields = record.fields.map { "\($0.name)=\($0.value)" }.joined(separator: " ")
        return "\(record.category.rawValue) \(record.event.rawValue) \(fields)"
    }.joined(separator: "\n")
}
