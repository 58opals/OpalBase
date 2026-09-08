// DiagnosticsValidator~WalletOperations.swift

import Foundation
import OpalDiagnostics
import Testing
import OpalBaseTestSupport
import SwiftFulcrum
@testable import OpalBase

extension DiagnosticsValidator {
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
}
