// AccountCommandValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Account Command", .tags(.unit, .wallet))
struct AccountCommandValidator {
    @Test("broadcast propagates cancellation without wrapping account failures")
    func propagateBroadcastCancellationWithoutAccountFailureWrapping() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x47),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data([0x51])
                )
            ],
            outputs: [
                .init(
                    value: 1_000,
                    lockingScript: Data([0x51])
                )
            ],
            lockTime: 0
        )
        let client = OpalBase.Network.TransactionClient(
            broadcastTransaction: { _ in throw CancellationError() },
            fetchConfirmations: { _ in nil },
            fetchConfirmationStatus: Self.makeUnconfirmedStatus
        )

        await #expect(throws: CancellationError.self) {
            _ = try await account.broadcast(transaction, via: client)
        }
    }

    @Test("confirmation monitor completes cleanly when confirmation fetch is cancelled")
    func finishConfirmationMonitorWhenConfirmationFetchIsCancelled() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let transactionHash = AccountTestFixtures.makeHash(byte: 0x48)
        let client = OpalBase.Network.TransactionClient(
            broadcastTransaction: { _ in transactionHash.reverseOrder.hexadecimalString },
            fetchConfirmations: { _ in throw CancellationError() },
            fetchConfirmationStatus: Self.makeUnconfirmedStatus
        )

        var iterator = await account.monitorConfirmations(
            for: transactionHash,
            via: client,
            pollInterval: .milliseconds(1)
        ).makeAsyncIterator()
        let firstValue = try await iterator.next()

        #expect(firstValue == nil)
    }

    @Test("transaction history refresh propagates cancellation from the history reader")
    func propagateTransactionHistoryReaderCancellationWithoutAccountFailureWrapping() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let cancellingHistoryReader = OpalBase.Network.AddressReader(
            fetchBalance: { _, _ in .init(confirmed: 0, unconfirmed: 0) },
            fetchUnspentOutputs: { _, _ in .init() },
            fetchHistory: { _, _ in throw CancellationError() },
            fetchFirstUse: { _ in nil },
            fetchMempoolTransactions: { _ in .init() },
            fetchScriptHash: { _ in "" },
            subscribeToAddress: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )

        await #expect(throws: CancellationError.self) {
            _ = try await account.refreshTransactionHistory(using: cancellingHistoryReader, usage: .receiving)
        }
    }

    private static func makeUnconfirmedStatus(
        for transactionHash: OpalBase.Transaction.Hash
    ) -> OpalBase.Network.TransactionConfirmationStatus {
        .init(transactionHash: transactionHash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
    }

    static func requireAccountTransactionBuildFailure(
        underlying expectedUnderlying: OpalBase.Address.Book.Error,
        operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
            throw ExpectedAccountTransactionBuildFailureNotThrown()
        } catch OpalBase.Account.Error.transactionBuildFailed(let underlying) {
            let typedUnderlying = try #require(underlying as? OpalBase.Address.Book.Error)
            #expect(typedUnderlying == expectedUnderlying)
        }
    }

    struct ExpectedAccountTransactionBuildFailureNotThrown: Swift.Error, CustomStringConvertible {
        var description: String {
            "Expected an account transaction build failure."
        }
    }

    enum StaleSelectedUTXORefreshCase: CaseIterable, CustomStringConvertible, Sendable {
        case missing
        case changedMetadata

        var description: String {
            switch self {
            case .missing:
                "missing selected UTXO"
            case .changedMetadata:
                "changed selected UTXO metadata"
            }
        }

        var hashByte: UInt8 {
            switch self {
            case .missing:
                0x49
            case .changedMetadata:
                0x4A
            }
        }

        func refreshedUTXOs(
            replacing utxo: OpalBase.Transaction.Output.Unspent
        ) -> [OpalBase.Transaction.Output.Unspent] {
            switch self {
            case .missing:
                []
            case .changedMetadata:
                [
                    OpalBase.Transaction.Output.Unspent(
                        value: 30_000,
                        lockingScript: utxo.lockingScript,
                        previousTransactionHash: utxo.previousTransactionHash,
                        previousTransactionOutputIndex: utxo.previousTransactionOutputIndex
                    )
                ]
            }
        }
    }

    enum StaleReservationRefreshAttemptCase: CaseIterable, CustomStringConvertible, Sendable {
        case originalPayload
        case replacementPayload

        var description: String {
            switch self {
            case .originalPayload:
                "original stale payload"
            case .replacementPayload:
                "replacement payload"
            }
        }

        func attemptedUTXOs(
            original: OpalBase.Transaction.Output.Unspent,
            replacement: OpalBase.Transaction.Output.Unspent
        ) -> [OpalBase.Transaction.Output.Unspent] {
            switch self {
            case .originalPayload:
                [original]
            case .replacementPayload:
                [replacement]
            }
        }

        func expectedError(
            replacement: OpalBase.Transaction.Output.Unspent
        ) -> OpalBase.Address.Book.Error {
            switch self {
            case .originalPayload:
                .utxoNotFound
            case .replacementPayload:
                .utxoAlreadyReserved(replacement)
            }
        }
    }

    @Test("prepareSpend reports insufficient funds when sweep-all shortfall occurs")
    func prepareSpendReportsShortfallForSweepAllCoinSelection() async throws {
        let account = try await AccountTestFixtures.makeAccount()

        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: OpalBase.Key.DerivationPath.Usage.receiving)
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 1_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([utxo])

        let recipientAddress = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let paymentAmount = try OpalBase.Satoshi(2_000)
        let payment = OpalBase.Account.Payment(
            recipients: [.init(address: recipientAddress, amount: paymentAmount)],
            coinSelection: .sweepAll
        )

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected prepareSpend to surface insufficient funds")
        } catch let error as OpalBase.Account.Error {
            switch error {
            case .coinSelectionFailed(let underlyingError):
                guard let transactionError = underlyingError as? OpalBase.Transaction.Error else {
                    Issue.record("Expected OpalBase.Transaction.Error but received \(type(of: underlyingError))")
                    return
                }

                switch transactionError {
                case .insufficientFunds(required: let requiredAmount):
                    let feeWithoutChange = try OpalBase.Transaction.estimateFee(
                        inputCount: 1,
                        outputs: [OpalBase.Transaction.Output(value: paymentAmount.uint64, address: recipientAddress, tokenData: nil)],
                        feePerByte: OpalBase.Wallet.FeePolicy().recommendFeeRate(for: payment.feeContext)
                    )
                    #expect(requiredAmount == paymentAmount.uint64 + feeWithoutChange - utxo.value)
                default:
                    Issue.record("Expected insufficient funds but received \(transactionError)")
                }
            default:
                Issue.record("Expected coinSelectionFailed but received \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("prepareSpend reports fee shortfall before reserving sweep-all funds")
    func prepareSpendReportsFeeShortfallBeforeReservingSweepAllFunds() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: OpalBase.Key.DerivationPath.Usage.receiving)
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 3, count: 32))
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 1_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([utxo])

        let recipientAddress = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let payment = OpalBase.Account.Payment(
            recipients: [.init(address: recipientAddress, amount: try OpalBase.Satoshi(1_000))],
            coinSelection: .sweepAll
        )

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected prepareSpend to reject sweep-all fee shortfall")
        } catch let error as OpalBase.Account.Error {
            switch error {
            case .coinSelectionFailed(let underlyingError):
                guard case OpalBase.Transaction.Error.insufficientFunds(required: let requiredAmount) = underlyingError else {
                    Issue.record("Expected insufficient funds but received \(underlyingError)")
                    return
                }
                #expect(requiredAmount > 0)
            default:
                Issue.record("Expected coinSelectionFailed but received \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("prepareSpend rejects dust recipients before reserving funds")
    func prepareSpendRejectsDustRecipientsBeforeReservingFunds() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 25_000,
            hashByte: 0x39
        )

        let recipientAddress = try OpalBase.Address(AccountTestFixtures.standardAddressString)
        let payment = OpalBase.Account.Payment(
            recipients: [.init(address: recipientAddress, amount: try OpalBase.Satoshi(1))]
        )

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected prepareSpend to reject a dust recipient output")
        } catch let error as OpalBase.Account.Error {
            guard case .coinSelectionFailed(let underlyingError) = error,
                  case OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit = underlyingError else {
                Issue.record("Expected outputValueIsLessThanTheDustLimit but received \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("prepareSpend reserves spend resources until explicitly released")
    func prepareSpendReservesUntilReleased() async throws {
        let account = try await AccountTestFixtures.makeAccount()

        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: OpalBase.Key.DerivationPath.Usage.receiving)
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 1, count: 32))
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 25_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([utxo])

        let recipientAddress = try OpalBase.Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let paymentAmount = try OpalBase.Satoshi(10_000)
        let payment = OpalBase.Account.Payment(recipients: [.init(address: recipientAddress, amount: paymentAmount)])

        let initialPlan = try await account.prepareSpend(payment)
        let initialChangeEntries = await addressBook.listEntries(for: OpalBase.Key.DerivationPath.Usage.change)
        let initialFirstChange = try #require(initialChangeEntries.first { $0.derivationPath.index == 0 })
        #expect(initialFirstChange.isUsed == true)
        #expect(initialFirstChange.isReserved == true)
        let gapLimit = await addressBook.readGapLimit()
        let initialUnusedCount = initialChangeEntries.filter { !$0.isUsed }.count
        #expect(initialUnusedCount >= gapLimit)

        do {
            _ = try await account.prepareSpend(payment)
            Issue.record("Expected subsequent prepareSpend call to fail while reservation is active")
        } catch { }

        try await initialPlan.cancelReservation()

        let afterCancellationEntries = await addressBook.listEntries(for: OpalBase.Key.DerivationPath.Usage.change)
        let restoredFirstChange = try #require(afterCancellationEntries.first { $0.derivationPath.index == 0 })
        #expect(restoredFirstChange.isUsed == false)
        #expect(restoredFirstChange.isReserved == false)
        let afterCancellationUnusedCount = afterCancellationEntries.filter { !$0.isUsed }.count
        #expect(afterCancellationUnusedCount >= gapLimit)

        let completedPlan = try await account.prepareSpend(payment)
        try await completedPlan.completeReservation()

        let afterCompletionEntries = await addressBook.listEntries(for: OpalBase.Key.DerivationPath.Usage.change)
        let completedFirstChange = try #require(afterCompletionEntries.first { $0.derivationPath.index == 0 })
        #expect(completedFirstChange.isUsed == true)
        #expect(completedFirstChange.isReserved == false)
        let afterCompletionUnusedCount = afterCompletionEntries.filter { !$0.isUsed }.count
        #expect(afterCompletionUnusedCount >= gapLimit)
        #expect(await addressBook.listSpendableUTXOs().contains(utxo) == false)

        let replacementUTXO = OpalBase.Transaction.Output.Unspent(
            value: 25_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 2, count: 32)),
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([replacementUTXO])
        let reusablePlan = try await account.prepareSpend(payment)
        try await reusablePlan.cancelReservation()
    }

    @Test("snapshot restore clears stale reservation flags")
    func snapshotRestoreClearsStaleReservationFlags() async throws {
        let wallet = try await AccountTestFixtures.makeWallet()
        let account = try await wallet.fetchAccount(at: 0)
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 25_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x45),
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([utxo])

        let recipientAddress = try OpalBase.Address(AccountTestFixtures.standardAddressString)
        let payment = OpalBase.Account.Payment(
            recipients: [.init(address: recipientAddress, amount: try OpalBase.Satoshi(10_000))]
        )
        _ = try await account.prepareSpend(payment)

        let reservedChangeEntry = try #require(
            await addressBook.listEntries(for: .change).first { $0.isReserved }
        )
        #expect(reservedChangeEntry.isUsed)

        let snapshot = await wallet.makeSnapshot()
        let restoredWallet = try await OpalBase.Wallet(
            mnemonic: try OpalBase.Key.Mnemonic(
                words: AccountTestFixtures.mnemonicWords.map(OpalBase.Key.Mnemonic.Word.init)
            ),
            from: snapshot
        )
        let restoredAccount = try await restoredWallet.fetchAccount(at: 0)
        let restoredAddressBook = await restoredAccount.addressBook
        let restoredChangeEntry = try #require(
            await restoredAddressBook.listEntries(for: OpalBase.Key.DerivationPath.Usage.change).first {
                $0.derivationPath.index == reservedChangeEntry.derivationPath.index
            }
        )

        #expect(restoredChangeEntry.isUsed)
        #expect(restoredChangeEntry.isReserved == false)
        #expect(await restoredAddressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("snapshot restore clears stale reserved UTXOs")
    func snapshotRestoreClearsStaleReservedUTXOs() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 25_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x46),
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([utxo])

        let recipientAddress = try OpalBase.Address(AccountTestFixtures.standardAddressString)
        let payment = OpalBase.Account.Payment(
            recipients: [.init(address: recipientAddress, amount: try OpalBase.Satoshi(10_000))]
        )
        _ = try await account.prepareSpend(payment)
        #expect(await addressBook.listSpendableUTXOs().contains(utxo) == false)

        let snapshot = await addressBook.makeSnapshot()
        try await addressBook.refresh(with: snapshot)

        #expect(await addressBook.readActiveSpendReservations().isEmpty)
        #expect(await addressBook.listUTXOs().contains(utxo))
        #expect(await addressBook.listSpendableUTXOs().contains(utxo))
    }

    @Test("reserveSpend refreshes a stale change entry when the preferred entry is already reserved")
    func reserveSpendRefreshesReservedStaleChangeEntry() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let firstUTXO = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 25_000,
            hashByte: 0x41
        )
        let secondUTXO = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 26_000,
            hashByte: 0x42
        )
        let staleChangeEntry = try await addressBook.selectNextEntry(for: .change)

        let firstReservation = try await addressBook.reserveSpend(
            utxos: [firstUTXO],
            changeEntry: staleChangeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )
        let secondReservation = try await addressBook.reserveSpend(
            utxos: [secondUTXO],
            changeEntry: staleChangeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )

        #expect(firstReservation.changeEntry.address == staleChangeEntry.address)
        #expect(secondReservation.changeEntry.address != staleChangeEntry.address)
        #expect(secondReservation.changeEntry.derivationPath.index == staleChangeEntry.derivationPath.index + 1)

        try await addressBook.releaseSpendReservation(secondReservation, outcome: .cancelled)
        try await addressBook.releaseSpendReservation(firstReservation, outcome: .cancelled)
    }

    @Test("stale spend reservation handles cannot release refreshed reservations")
    func staleSpendReservationHandlesCannotReleaseRefreshedReservations() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let utxo = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 25_000,
            hashByte: 0x47
        )
        let changeEntry = try await addressBook.selectNextEntry(for: .change)

        let firstReservation = try await addressBook.reserveSpend(
            utxos: [utxo],
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )
        try await Task.sleep(for: .milliseconds(10))
        let refreshedReservation = try await addressBook.reserveSpend(
            utxos: [utxo],
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )

        #expect(firstReservation.id == refreshedReservation.id)
        #expect(firstReservation.reservationDate != refreshedReservation.reservationDate)

        try await addressBook.releaseSpendReservation(firstReservation, outcome: .cancelled)

        #expect(await addressBook.readActiveSpendReservations().count == 1)
        #expect(await addressBook.listSpendableUTXOs().contains(utxo) == false)

        try await addressBook.releaseSpendReservation(refreshedReservation, outcome: .cancelled)

        #expect(await addressBook.readActiveSpendReservations().isEmpty)
        #expect(await addressBook.listSpendableUTXOs().contains(utxo))
    }

    @Test(
        "reserveSpend rejects stale reservation refresh attempts after selected UTXO metadata changes",
        arguments: StaleReservationRefreshAttemptCase.allCases
    )
    func reserveSpendRejectsStaleReservationRefreshAttemptsAfterSelectedUTXOMetadataChanges(
        _ attemptCase: StaleReservationRefreshAttemptCase
    ) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 25_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x4C),
            previousTransactionOutputIndex: 0
        )
        let replacementUTXO = try #require(
            StaleSelectedUTXORefreshCase.changedMetadata.refreshedUTXOs(replacing: utxo).first
        )
        await addressBook.addUTXOs([utxo])
        let changeEntry = try await addressBook.selectNextEntry(for: .change)

        let reservation = try await addressBook.reserveSpend(
            utxos: [utxo],
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )
        _ = try await addressBook.refreshUTXOSet(
            using: AddressReaderClient(unspentByAddress: [
                receivingEntry.address.string: [replacementUTXO]
            ]),
            usage: .receiving
        )

        await #expect(throws: attemptCase.expectedError(replacement: replacementUTXO)) {
            _ = try await addressBook.reserveSpend(
                utxos: attemptCase.attemptedUTXOs(
                    original: utxo,
                    replacement: replacementUTXO
                ),
                changeEntry: changeEntry,
                tokenSelectionPolicy: .excludeTokenUTXOs
            )
        }

        let activeReservation = try #require(await addressBook.readActiveSpendReservations().first)
        #expect(activeReservation.id == reservation.id)

        try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
    }

    @Test(
        "completeReservation rejects reservations whose selected UTXO is stale",
        arguments: StaleSelectedUTXORefreshCase.allCases
    )
    func completeReservationRejectsReservationsWithStaleSelectedUTXOs(_ refreshCase: StaleSelectedUTXORefreshCase) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
        let transactionHash = AccountTestFixtures.makeHash(byte: refreshCase.hashByte)
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 25_000,
            lockingScript: receivingEntry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([utxo])

        let recipientAddress = try OpalBase.Address(AccountTestFixtures.standardAddressString)
        let payment = OpalBase.Account.Payment(
            recipients: [.init(address: recipientAddress, amount: try OpalBase.Satoshi(10_000))]
        )
        let plan = try await account.prepareSpend(payment)
        let reservedChangeEntry = try #require(await addressBook.listEntries(for: .change).first { $0.isReserved })

        _ = try await addressBook.refreshUTXOSet(
            using: AddressReaderClient(unspentByAddress: [
                receivingEntry.address.string: refreshCase.refreshedUTXOs(replacing: utxo)
            ]),
            usage: .receiving
        )

        try await Self.requireAccountTransactionBuildFailure(underlying: .utxoNotFound) {
            try await plan.completeReservation()
        }
        let refreshedChangeEntry = try #require(
            await addressBook.listEntries(for: .change).first {
                $0.derivationPath.index == reservedChangeEntry.derivationPath.index
            }
        )
        #expect(refreshedChangeEntry.isUsed == false)
        #expect(refreshedChangeEntry.isReserved == false)
        #expect(await addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("reserveSpend rejects empty input sets before reserving change")
    func reserveSpendRejectsEmptyInputSetsBeforeReservingChange() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let changeEntry = try await addressBook.selectNextEntry(for: .change)

        await #expect(throws: OpalBase.Address.Book.Error.utxoNotFound) {
            _ = try await addressBook.reserveSpend(
                utxos: [],
                changeEntry: changeEntry,
                tokenSelectionPolicy: .excludeTokenUTXOs
            )
        }

        let changeEntries = await addressBook.listEntries(for: .change)
        let firstChangeEntry = try #require(
            changeEntries.first { $0.derivationPath.index == changeEntry.derivationPath.index }
        )
        #expect(firstChangeEntry.isReserved == false)
        #expect(await addressBook.readActiveSpendReservations().isEmpty)
    }

    @Test("reserveSpend rejects duplicate input sets before reserving change")
    func reserveSpendRejectsDuplicateInputSetsBeforeReservingChange() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let utxo = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 25_000,
            hashByte: 0x48
        )
        let changeEntry = try await addressBook.selectNextEntry(for: .change)

        await #expect(throws: OpalBase.Address.Book.Error.utxoDuplicated(utxo)) {
            _ = try await addressBook.reserveSpend(
                utxos: [utxo, utxo],
                changeEntry: changeEntry,
                tokenSelectionPolicy: .excludeTokenUTXOs
            )
        }

        let changeEntries = await addressBook.listEntries(for: .change)
        let firstChangeEntry = try #require(
            changeEntries.first { $0.derivationPath.index == changeEntry.derivationPath.index }
        )
        #expect(firstChangeEntry.isReserved == false)
        #expect(await addressBook.readActiveSpendReservations().isEmpty)
        #expect(await addressBook.listSpendableUTXOs().contains(utxo))
    }

    @Test("reserveSpend does not reuse a completed stale change entry")
    func reserveSpendAvoidsReusingCompletedStaleChangeEntry() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let firstUTXO = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 25_000,
            hashByte: 0x43
        )
        let secondUTXO = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 26_000,
            hashByte: 0x44
        )
        let staleChangeEntry = try await addressBook.selectNextEntry(for: .change)

        let firstReservation = try await addressBook.reserveSpend(
            utxos: [firstUTXO],
            changeEntry: staleChangeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )
        try await addressBook.releaseSpendReservation(firstReservation, outcome: .completed)

        let secondReservation = try await addressBook.reserveSpend(
            utxos: [secondUTXO],
            changeEntry: staleChangeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )

        #expect(secondReservation.changeEntry.address != staleChangeEntry.address)
        #expect(secondReservation.changeEntry.derivationPath.index == staleChangeEntry.derivationPath.index + 1)

        let changeEntries = await addressBook.listEntries(for: .change)
        let completedChangeEntry = changeEntries.first {
            $0.derivationPath.index == staleChangeEntry.derivationPath.index
        }
        let completedEntry = try #require(completedChangeEntry)
        #expect(completedEntry.isUsed == true)
        #expect(completedEntry.isReserved == false)

        try await addressBook.releaseSpendReservation(secondReservation, outcome: .cancelled)
    }

    @Test("reserveNextReceivingEntry advances receiving entries")
    func reserveNextReceivingEntryAdvancesReceivingEntries() async throws {
        let account = try await AccountTestFixtures.makeAccount()

        let firstReservedEntry = try await account.reserveNextReceivingEntry()
        #expect(firstReservedEntry.derivationPath.index == 0)
        #expect(firstReservedEntry.isReserved == true)
        #expect(firstReservedEntry.isUsed == true)

        let secondReservedEntry = try await account.reserveNextReceivingEntry()
        #expect(secondReservedEntry.derivationPath.index == 1)
        #expect(secondReservedEntry.isReserved == true)
        #expect(secondReservedEntry.isUsed == true)
        #expect(secondReservedEntry.address != firstReservedEntry.address)

        let nextAvailableEntry = try await account.addressBook.selectNextEntry(for: OpalBase.Key.DerivationPath.Usage.receiving)
        #expect(nextAvailableEntry.derivationPath.index == 2)
        #expect(nextAvailableEntry.isReserved == false)
        #expect(nextAvailableEntry.isUsed == false)
    }
}
