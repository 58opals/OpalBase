// DiagnosticsValidator.swift

import Foundation
import OpalDiagnostics
import Testing
import OpalBaseTestSupport
import SwiftFulcrum
@testable import OpalBase

@Suite("OpalDiagnostics", .tags(.unit, .wallet))
struct DiagnosticsValidator {
    @Test("public diagnostics catalog exposes stable names")
    func publicDiagnosticsCatalogExposesStableNames() {
        #expect(Set(OpalDiagnostics.Category.all) == [
            OpalDiagnostics.Category.wallet,
            OpalDiagnostics.Category.account,
            OpalDiagnostics.Category.addressBook,
            OpalDiagnostics.Category.network,
            OpalDiagnostics.Category.cashFusion,
            OpalDiagnostics.Category.hedge,
            OpalDiagnostics.Category.transaction,
            OpalDiagnostics.Category.claimable,
            OpalDiagnostics.Category.tokenMetadata,
            OpalDiagnostics.Category.storage
        ])

        #expect(OpalDiagnostics.ErrorCode.all.contains(OpalDiagnostics.ErrorCode.cashFusionReservationFailed))
    }

    @Test(
        "public diagnostics catalog contains representative events",
        arguments: DiagnosticsCatalogEventCase.allCases
    )
    func publicDiagnosticsCatalogContainsRepresentativeEvents(
        eventCase: DiagnosticsCatalogEventCase
    ) {
        #expect(OpalDiagnostics.Event.all.contains(eventCase.event))
    }

    @Test(
        "stable diagnostics event raw values",
        arguments: StableDiagnosticsEventRawValueCase.allCases
    )
    func stableDiagnosticsEventRawValues(
        eventCase: StableDiagnosticsEventRawValueCase
    ) {
        let expectation = eventCase.rawValueExpectation
        #expect(expectation.event.rawValue == expectation.rawValue)
    }

    @Test(
        "stable diagnostics field names",
        arguments: StableDiagnosticsFieldNameCase.allCases
    )
    func stableDiagnosticsFieldNames(
        fieldCase: StableDiagnosticsFieldNameCase
    ) {
        let expectation = fieldCase.rawValueExpectation
        #expect(expectation.fieldName == expectation.rawValue)
    }

    @Test(
        "public diagnostics catalog contains representative fields",
        arguments: DiagnosticsCatalogFieldNameCase.allCases
    )
    func publicDiagnosticsCatalogContainsRepresentativeFields(
        fieldCase: DiagnosticsCatalogFieldNameCase
    ) {
        #expect(OpalDiagnostics.Field.Name.all.contains(fieldCase.fieldName))
    }

    @Test(
        "stable error code raw values",
        arguments: StableErrorCodeRawValueCase.allCases
    )
    func stableErrorCodeRawValues(
        rawValueCase: StableErrorCodeRawValueCase
    ) {
        let expectation = rawValueCase.rawValueExpectation
        #expect(expectation.errorCode.rawValue == expectation.rawValue)
    }

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

    @Test("Fulcrum diagnostics follow OpalDiagnostics configuration", .timeLimit(.minutes(1)))
    func fulcrumDiagnosticsFollowOpalDiagnosticsConfiguration() async {
        let configuredRecords = await failedFulcrumStartupBridgeRecords(configuration: diagnosticsConfiguration())
        #expect(configuredRecords.contains {
            $0.event == OpalDiagnostics.Event.networkFulcrumClientFailed
        })

        let defaultRecords = await failedFulcrumStartupBridgeRecords(configuration: .init())
        #expect(defaultRecords.isEmpty)
    }

    @Test("wallet operations propagate trace IDs into lower diagnostics")
    func walletOperationsPropagateTraceIDsIntoLowerDiagnostics() async throws {
        let traceID = OpalDiagnostics.TraceID()
        let records = try await OpalDiagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            try await OpalDiagnostics.withTraceID(traceID) {
                let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
                try await wallet.addAccount(unhardenedIndex: 0)
                _ = try await wallet.fetchAccount(at: 0)
            }

            return OpalDiagnostics.recentRecords.filter { $0.traceID == traceID }
        }

        #expect(records.contains { $0.event == OpalDiagnostics.Event.walletCreateStarted })
        #expect(records.contains { $0.event == OpalDiagnostics.Event.walletAccountCreateSucceeded })
        #expect(records.contains { $0.event == OpalDiagnostics.Event.walletAccountFetchSucceeded })
        #expect(records.contains { $0.event.rawValue.hasPrefix("opalcrypto.") })
        #expect(records.allSatisfy { $0.traceID == traceID })
    }

    @Test("hedge participant reservation emits boundary diagnostics")
    func hedgeParticipantReservationEmitsBoundaryDiagnostics() async throws {
        let records = try await OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            let account = try await AccountTestFixtures.makeAccount()
            _ = try await account.reserveHedgeParticipantMaterial(network: .chipnet)

            return OpalDiagnostics.recentRecords(
                category: OpalDiagnostics.Category.hedge
            )
        }

        #expect(records.contains {
            $0.event == OpalDiagnostics.Event.hedgeParticipantMaterialReserveStarted
        })
        #expect(records.contains {
            $0.event == OpalDiagnostics.Event.hedgeParticipantMaterialReserved
        })
    }

    @Test("hedge funding prepare failures use the hedge error code")
    func hedgeFundingPrepareFailuresUseHedgeErrorCode() async throws {
        let records = try await OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            let account = try await AccountTestFixtures.makeAccount()
            let request = try await makeDiagnosticsHedgeFundingRequest(for: account)

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await account.prepareHedgeFunding(request)
            }

            return OpalDiagnostics.recentRecords(category: OpalDiagnostics.Category.hedge)
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.hedgeFundingPrepareFailed,
            errorCode: OpalDiagnostics.ErrorCode.hedgeFundingFailed
        ))
    }

    @Test("hedge funding broadcast failures use the hedge error code")
    func hedgeFundingBroadcastFailuresUseHedgeErrorCode() async throws {
        let records = try await OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
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

            return OpalDiagnostics.recentRecords(category: OpalDiagnostics.Category.hedge)
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.hedgeFundingBroadcastFailed,
            errorCode: OpalDiagnostics.ErrorCode.hedgeFundingFailed
        ))
    }

    @Test("recent diagnostics redact sensitive values and use safe field names")
    func recentDiagnosticsRedactSensitiveValuesAndUseSafeFieldNames() async throws {
        let mnemonic = try AccountTestFixtures.makeMnemonic()
        let result = try await OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
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

            OpalDiagnostics.record(
                OpalDiagnostics.Event.walletCreateStarted,
                category: OpalDiagnostics.Category.wallet,
                fields: sensitiveValues.enumerated().map { index, value in
                    OpalDiagnostics.Field.privateValue("private_payload_\(index)", value)
                }
            )

            return (records: OpalDiagnostics.recentRecords, sensitiveValues: sensitiveValues)
        }

        let renderedRecords = render(result.records)
        for sensitiveValue in result.sensitiveValues {
            #expect(renderedRecords.contains(sensitiveValue) == false)
        }

        let fieldNames = OpalDiagnostics.Field.Name.all.joined(separator: " ")
        for forbiddenNameFragment in [
            "mnemonic", "seed", "private_key", "wif", "full_address", "raw_transaction",
            "contract_json", "oracle_message", "oracle_signature", "redeem_script", "raw_proof"
        ] {
            #expect(fieldNames.contains(forbiddenNameFragment) == false)
        }
    }

    @Test("error code fields remain stable")
    func errorCodeFieldsRemainStable() async throws {
        let records = try await OpalDiagnostics.withConfiguration(
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

            return OpalDiagnostics.recentRecords
        }

        #expect(errorCodes(in: records).contains(OpalDiagnostics.ErrorCode.walletAccountAlreadyExists))
        #expect(errorCodes(in: records).contains(OpalDiagnostics.ErrorCode.walletAccountNotFound))
        #expect(errorCodes(in: records).contains(OpalDiagnostics.ErrorCode.claimableInvalidShareCode))
    }

    @Test(
        "SwiftFulcrum errors use stable network error codes",
        arguments: SwiftFulcrumStableCodeCase.allCases
    )
    func swiftFulcrumErrorsUseStableNetworkErrorCodes(
        stableCodeCase: SwiftFulcrumStableCodeCase
    ) {
        #expect(OpalDiagnostics.ErrorCode.opalBaseCode(for: stableCodeCase.error) == stableCodeCase.expectedCode)
    }

    @Test("balance refresh failures use a stable error code")
    func balanceRefreshFailuresUseStableErrorCode() async throws {
        let records = try await OpalDiagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
            try await wallet.addAccount(unhardenedIndex: 0)

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await wallet.calculateBalance { _ in
                    throw NetworkStubError.forced("balance-refresh")
                }
            }

            return OpalDiagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.walletBalanceRefreshFailed,
            errorCode: OpalDiagnostics.ErrorCode.accountBalanceRefreshFailed
        ))
    }

    @Test("transaction history failures use a stable error code")
    func transactionHistoryFailuresUseStableErrorCode() async throws {
        let records = try await OpalDiagnostics.withConfiguration(
            diagnosticsConfiguration()
        ) {
            let account = try await AccountTestFixtures.makeAccount()
            let reader = makeDiagnosticsAddressReader { _, _ in
                throw NetworkStubError.forced("history-refresh")
            }

            await #expect(throws: OpalBase.Account.Error.self) {
                _ = try await account.refreshTransactionHistory(using: reader)
            }

            return OpalDiagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.transactionHistoryRefreshFailed,
            errorCode: OpalDiagnostics.ErrorCode.accountTransactionHistoryRefreshFailed
        ))
    }

    @Test("transaction detail refresh failures use a stable error code")
    func transactionDetailRefreshFailuresUseStableErrorCode() async throws {
        let records = try await OpalDiagnostics.withConfiguration(
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

            return OpalDiagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.transactionHistoryRefreshFailed,
            errorCode: OpalDiagnostics.ErrorCode.accountTransactionDetailsRefreshFailed
        ))
    }

    @Test("insufficient funds use the stable insufficient funds error code")
    func insufficientFundsUseStableInsufficientFundsErrorCode() async throws {
        let records = try await OpalDiagnostics.withConfiguration(
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

            return OpalDiagnostics.recentRecords
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.spendPrepareFailed,
            errorCode: OpalDiagnostics.ErrorCode.accountInsufficientFunds
        ))
    }

    @Test("empty confirmation refresh records diagnostics")
    func emptyConfirmationRefreshRecordsDiagnostics() async throws {
        let records = try await OpalDiagnostics.withConfiguration(
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

            return OpalDiagnostics.recentRecords
        }

        #expect(records.contains {
            $0.event == OpalDiagnostics.Event.transactionConfirmationRefreshStarted
        })
        let succeededRecords = records.filter {
            $0.event == OpalDiagnostics.Event.transactionConfirmationRefreshSucceeded
        }
        #expect(succeededRecords.contains { record in
            record.fields.contains {
                $0.name == OpalDiagnostics.Field.Name.transactionCount &&
                    $0.value == "0"
            }
        })
    }

    @Test("claimable envelope network mismatches record failure diagnostics")
    func claimableEnvelopeNetworkMismatchesRecordFailureDiagnostics() throws {
        let records = try OpalDiagnostics.withConfiguration(diagnosticsConfiguration()) {
            let (envelope, _) = try makeClaimableEnvelope(network: .chipnet)
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

            return OpalDiagnostics.recentRecords(category: OpalDiagnostics.Category.claimable)
        }

        #expect(recordsContain(
            records,
            event: OpalDiagnostics.Event.claimableStatusResolveFailed,
            errorCode: OpalDiagnostics.ErrorCode.claimableStatusFailed
        ))
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

    enum SwiftFulcrumStableCodeCase: CaseIterable, Sendable {
        case clientTimeout
        case heartbeatTimeout
        case decode

        var error: SwiftFulcrum.Client.Error {
            switch self {
            case .clientTimeout:
                return .client(.timeout(.seconds(3)))
            case .heartbeatTimeout:
                return .transport(.heartbeatTimeout)
            case .decode:
                return .coding(.decode(nil))
            }
        }

        var expectedCode: OpalDiagnostics.ErrorCode {
            switch self {
            case .clientTimeout,
                 .heartbeatTimeout:
                return .networkTimeout
            case .decode:
                return .networkDecoding
            }
        }
    }

    enum DiagnosticsCatalogEventCase: CaseIterable, Sendable {
        case walletCreateStarted
        case addressReserveSucceeded
        case utxoRefreshFailed
        case spendPrepareStarted
        case cashFusionSessionFinalized
        case hedgeParticipantMaterialReserveStarted
        case hedgeFundingBroadcastFailed
        case claimableShareCodeDecodeFailed
        case tokenMetadataSyncSucceeded
        case networkDiagnosticsCountersRecorded
        case networkDiagnosticsRegistryUpdateRecorded

        var event: OpalDiagnostics.Event {
            switch self {
            case .walletCreateStarted:
                return .walletCreateStarted
            case .addressReserveSucceeded:
                return .addressReserveSucceeded
            case .utxoRefreshFailed:
                return .utxoRefreshFailed
            case .spendPrepareStarted:
                return .spendPrepareStarted
            case .cashFusionSessionFinalized:
                return .cashFusionSessionFinalized
            case .hedgeParticipantMaterialReserveStarted:
                return .hedgeParticipantMaterialReserveStarted
            case .hedgeFundingBroadcastFailed:
                return .hedgeFundingBroadcastFailed
            case .claimableShareCodeDecodeFailed:
                return .claimableShareCodeDecodeFailed
            case .tokenMetadataSyncSucceeded:
                return .tokenMetadataSyncSucceeded
            case .networkDiagnosticsCountersRecorded:
                return .networkDiagnosticsCountersRecorded
            case .networkDiagnosticsRegistryUpdateRecorded:
                return .networkDiagnosticsRegistryUpdateRecorded
            }
        }
    }

    enum StableDiagnosticsEventRawValueCase: CaseIterable, Sendable {
        case networkDiagnosticsCountersRecorded
        case networkDiagnosticsRegistryUpdateRecorded

        var rawValueExpectation: (event: OpalDiagnostics.Event, rawValue: String) {
            switch self {
            case .networkDiagnosticsCountersRecorded:
                return (
                    .networkDiagnosticsCountersRecorded,
                    "opalbase.network.diagnostics.snapshot.recorded"
                )
            case .networkDiagnosticsRegistryUpdateRecorded:
                return (
                    .networkDiagnosticsRegistryUpdateRecorded,
                    "opalbase.network.diagnostics.subscriptions.recorded"
                )
            }
        }
    }

    enum StableDiagnosticsFieldNameCase: CaseIterable, Sendable {
        case errorCode
        case accountIndex
        case accountCount
        case tokenMetadataCount
        case errorReason
        case serverCode
        case closeCode
        case timeoutSeconds
        case minimumVersion
        case maximumVersion
        case privateErrorMetadata

        var rawValueExpectation: (fieldName: String, rawValue: String) {
            switch self {
            case .errorCode:
                return (OpalDiagnostics.Field.Name.errorCode, "error_code")
            case .accountIndex:
                return (OpalDiagnostics.Field.Name.accountIndex, "account_index")
            case .accountCount:
                return (OpalDiagnostics.Field.Name.accountCount, "account_count")
            case .tokenMetadataCount:
                return (OpalDiagnostics.Field.Name.tokenMetadataCount, "token_metadata_count")
            case .errorReason:
                return (OpalDiagnostics.Field.Name.errorReason, "error_reason")
            case .serverCode:
                return (OpalDiagnostics.Field.Name.serverCode, "server_code")
            case .closeCode:
                return (OpalDiagnostics.Field.Name.closeCode, "close_code")
            case .timeoutSeconds:
                return (OpalDiagnostics.Field.Name.timeoutSeconds, "timeout_seconds")
            case .minimumVersion:
                return (OpalDiagnostics.Field.Name.minimumVersion, "minimum_version")
            case .maximumVersion:
                return (OpalDiagnostics.Field.Name.maximumVersion, "maximum_version")
            case .privateErrorMetadata:
                return (OpalDiagnostics.Field.Name.privateErrorMetadata, "error_private_metadata")
            }
        }
    }

    enum DiagnosticsCatalogFieldNameCase: CaseIterable, Sendable {
        case reconnectionAttemptCount
        case activeSubscriptionCount
        case errorType
        case errorMessage

        var fieldName: String {
            switch self {
            case .reconnectionAttemptCount:
                return OpalDiagnostics.Field.Name.reconnectionAttemptCount
            case .activeSubscriptionCount:
                return OpalDiagnostics.Field.Name.activeSubscriptionCount
            case .errorType:
                return OpalDiagnostics.Field.Name.errorType
            case .errorMessage:
                return OpalDiagnostics.Field.Name.errorMessage
            }
        }
    }

    enum StableErrorCodeRawValueCase: CaseIterable, Sendable {
        case walletAccountAlreadyExists
        case walletAccountNotFound
        case accountBalanceRefreshFailed
        case accountTransactionHistoryRefreshFailed
        case networkTransport
        case networkServer
        case networkTimeout
        case networkEncoding
        case networkDecoding
        case networkProtocolViolation
        case claimableInvalidShareCode
        case hedgeFundingFailed

        var rawValueExpectation: (errorCode: OpalDiagnostics.ErrorCode, rawValue: String) {
            switch self {
            case .walletAccountAlreadyExists:
                return (.walletAccountAlreadyExists, "wallet.account_already_exists")
            case .walletAccountNotFound:
                return (.walletAccountNotFound, "wallet.account_not_found")
            case .accountBalanceRefreshFailed:
                return (.accountBalanceRefreshFailed, "account.balance_refresh_failed")
            case .accountTransactionHistoryRefreshFailed:
                return (.accountTransactionHistoryRefreshFailed, "account.transaction_history_refresh_failed")
            case .networkTransport:
                return (.networkTransport, "network.transport")
            case .networkServer:
                return (.networkServer, "network.server")
            case .networkTimeout:
                return (.networkTimeout, "network.timeout")
            case .networkEncoding:
                return (.networkEncoding, "network.encoding")
            case .networkDecoding:
                return (.networkDecoding, "network.decoding")
            case .networkProtocolViolation:
                return (.networkProtocolViolation, "network.protocol_violation")
            case .claimableInvalidShareCode:
                return (.claimableInvalidShareCode, "claimable.invalid_share_code")
            case .hedgeFundingFailed:
                return (.hedgeFundingFailed, "hedge.funding_failed")
            }
        }
    }
}

private func diagnosticsConfiguration(
    minimumLevel: OpalDiagnostics.Level = .debug,
    categoryFilter: OpalDiagnostics.CategoryFilter = .all
) -> OpalDiagnostics.Configuration {
    OpalDiagnostics.Configuration(
        minimumLevel: minimumLevel,
        categoryFilter: categoryFilter,
        bufferPolicy: .enabled(capacity: 512)
    )
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

private func errorCodes(in records: [OpalDiagnostics.Record]) -> Set<OpalDiagnostics.ErrorCode> {
    Set(
        records
            .flatMap(\.fields)
            .filter { $0.name == OpalDiagnostics.Field.Name.errorCode }
            .map { OpalDiagnostics.ErrorCode(rawValue: $0.value) }
    )
}

private func recordsContain(
    _ records: [OpalDiagnostics.Record],
    event: OpalDiagnostics.Event,
    errorCode: OpalDiagnostics.ErrorCode
) -> Bool {
    records.contains { record in
        record.event == event && recordContains(record, errorCode: errorCode)
    }
}

private func recordContains(
    _ record: OpalDiagnostics.Record,
    errorCode: OpalDiagnostics.ErrorCode
) -> Bool {
    record.fields.contains {
        $0.name == OpalDiagnostics.Field.Name.errorCode &&
            $0.value == errorCode.rawValue
    }
}

private func render(_ records: [OpalDiagnostics.Record]) -> String {
    records.map { record in
        let fields = record.fields.map { "\($0.name)=\($0.value)" }.joined(separator: " ")
        return "\(record.category.rawValue) \(record.event.rawValue) \(fields)"
    }.joined(separator: "\n")
}
