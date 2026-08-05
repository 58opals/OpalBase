// ReusablePaymentAddressRestorationValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Cash Code restoration", .tags(.unit, .wallet, .transaction))
struct ReusablePaymentAddressRestorationValidator {
    @Test("confirmed restoration commits bounded windows and deduplicates candidates")
    func restoreConfirmedHistoryAtomically() async throws {
        let fixture = try makePositiveFixture()
        let reference = OpalBase.ReusablePaymentAddress
            .ConfirmedTransactionReference(
                transactionHash: fixture.hash,
                blockHeight: 101
            )
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [reference, reference],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )

        let state = try await restoration.restoreConfirmed(
            upToHeightExclusive: 104,
            windowSize: 2
        )

        #expect(state.nextUnscannedHeight == 104)
        #expect(state.revision == 3)
        let match = try #require(state.confirmedMatches.first)
        #expect(state.confirmedMatches.count == 1)
        #expect(match.blockHeight == 101)
        #expect(match.output.transactionHash == fixture.hash)
        #expect(match.output.outputIndex == 0)
        #expect(match.output.value == 80_000)
        #expect(match.output.tokenData?.amount == 1)
        #expect(match.derivation.qualifyingInputIndex == 0)
        #expect(match.derivation.childIndex == 0)
        #expect(
            match.derivation.senderPublicKey.compressedData.hexadecimalString
                == ReusablePaymentAddressFixtureData
                    .senderCompressedPublicKey
        )
        #expect(
            await transportActor.readConfirmedRanges()
                == [100..<102, 102..<104]
        )
        #expect(
            await transportActor.readRawTransactionRequestCount(
                for: fixture.hash
            ) == 1
        )
        #expect(await persistenceActor.readSaveCount() == 3)
    }

    @Test("restoration restarts at the durable cursor and replays idempotently")
    func resumeAndReplayIdempotently() async throws {
        let fixture = try makePositiveFixture()
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [
                .init(transactionHash: fixture.hash, blockHeight: 101),
            ],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let first = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )
        _ = try await first.restoreConfirmed(
            upToHeightExclusive: 104,
            windowSize: 2
        )

        let restarted = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )
        let resumed = try await restarted.restoreConfirmed(
            upToHeightExclusive: 106,
            windowSize: 2
        )
        let saveCountAfterResume = await persistenceActor.readSaveCount()
        let replayed = try await restarted.restoreConfirmed(
            upToHeightExclusive: 106,
            windowSize: 2
        )

        #expect(resumed.nextUnscannedHeight == 106)
        #expect(resumed.confirmedMatches.count == 1)
        #expect(replayed == resumed)
        #expect(await persistenceActor.readSaveCount() == saveCountAfterResume)
        #expect(
            await transportActor.readConfirmedRanges()
                == [100..<102, 102..<104, 104..<106]
        )
    }

    @Test("cancellation before a window performs no transport or durable work")
    func cancelBeforeConfirmedWindow() async throws {
        let transportActor = ReusablePaymentAddressRestorationTransportActor()
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await restoration.restoreConfirmed(
                upToHeightExclusive: 101,
                windowSize: 1
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await transportActor.readConfirmedRanges().isEmpty)
        let state = await restoration.stateSnapshot
        #expect(state.nextUnscannedHeight == 100)
        #expect(state.revision == 1)
        #expect(await persistenceActor.readSaveCount() == 1)
    }

    @Test("cancellation during a window leaves state and cursor unchanged")
    func cancelDuringConfirmedWindow() async throws {
        let fixture = try makePositiveFixture()
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [
                .init(transactionHash: fixture.hash, blockHeight: 100),
            ],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )
        await transportActor.suspendNextConfirmedRequest()

        let task = Task {
            try await restoration.restoreConfirmed(
                upToHeightExclusive: 101,
                windowSize: 1
            )
        }
        await transportActor.waitForSuspendedConfirmedRequest()
        task.cancel()
        await transportActor.resumeConfirmedRequest()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        let state = await restoration.stateSnapshot
        #expect(state.nextUnscannedHeight == 100)
        #expect(state.confirmedMatches.isEmpty)
        #expect(state.revision == 1)
        #expect(await persistenceActor.readSaveCount() == 1)
    }

    @Test("persistence failure leaves the complete window unapplied")
    func preserveStateWhenWindowCommitFails() async throws {
        let fixture = try makePositiveFixture()
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [
                .init(transactionHash: fixture.hash, blockHeight: 100),
            ],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )
        await persistenceActor.failSavingRevision(2)

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .invalidPersistentState
        ) {
            _ = try await restoration.restoreConfirmed(
                upToHeightExclusive: 101,
                windowSize: 1
            )
        }

        let state = await restoration.stateSnapshot
        #expect(state.nextUnscannedHeight == 100)
        #expect(state.confirmedMatches.isEmpty)
        #expect(state.revision == 1)
        #expect((await persistenceActor.loadState())?.revision == 1)
    }

    @Test("mempool refresh removes stale matches and transitions confirmations")
    func refreshMempoolDeterministically() async throws {
        let fixture = try makePositiveFixture()
        let mempoolReference = OpalBase.ReusablePaymentAddress
            .MempoolTransactionReference(
                transactionHash: fixture.hash,
                fee: 900,
                hasUnconfirmedParent: false
            )
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            mempoolReferences: [mempoolReference, mempoolReference],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )

        let mempoolState = try await restoration.refreshMempool()
        #expect(mempoolState.mempoolMatches.count == 1)
        #expect(mempoolState.mempoolMatches[0].fee == 900)

        await transportActor.replaceMempoolReferences(with: [])
        let staleRemoved = try await restoration.refreshMempool()
        #expect(staleRemoved.mempoolMatches.isEmpty)

        await transportActor.replaceMempoolReferences(
            with: [mempoolReference]
        )
        _ = try await restoration.refreshMempool()
        await transportActor.replaceConfirmedReferences(
            with: [
                .init(transactionHash: fixture.hash, blockHeight: 100),
            ]
        )
        let confirmed = try await restoration.restoreConfirmed(
            upToHeightExclusive: 101,
            windowSize: 1
        )
        #expect(confirmed.confirmedMatches.count == 1)
        #expect(confirmed.mempoolMatches.isEmpty)
    }

    @Test("reorganization rollback is idempotent and supports deterministic replay")
    func rollBackAndReplayReorganization() async throws {
        let firstFixture = try makePositiveFixture()
        let secondFixture = try makePositiveFixture(lockTime: 1)
        let references: [
            OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference
        ] = [
            .init(transactionHash: firstFixture.hash, blockHeight: 101),
            .init(transactionHash: secondFixture.hash, blockHeight: 105),
        ]
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: references,
            rawTransactions: [
                firstFixture.hash: firstFixture.rawTransaction,
                secondFixture.hash: secondFixture.rawTransaction,
            ]
        )
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )
        _ = try await restoration.restoreConfirmed(
            upToHeightExclusive: 108,
            windowSize: 4
        )

        let rolledBack = try await restoration.applyReorganization(
            eventIdentifier: "header-chain:event-1",
            firstAffectedHeight: 104
        )
        let saveCount = await persistenceActor.readSaveCount()
        let repeated = try await restoration.applyReorganization(
            eventIdentifier: "header-chain:event-1",
            firstAffectedHeight: 104
        )

        #expect(rolledBack.nextUnscannedHeight == 104)
        #expect(rolledBack.confirmedMatches.map(\.blockHeight) == [101])
        #expect(repeated == rolledBack)
        #expect(await persistenceActor.readSaveCount() == saveCount)

        let replayed = try await restoration.restoreConfirmed(
            upToHeightExclusive: 108,
            windowSize: 4
        )
        #expect(replayed.nextUnscannedHeight == 108)
        #expect(replayed.confirmedMatches.map(\.blockHeight) == [101, 105])
        #expect(
            replayed.lastReorganization?.rollbackHeight == 104
        )

        let secondEvent = try await restoration.applyReorganization(
            eventIdentifier: "header-chain:event-2",
            firstAffectedHeight: 106
        )
        let saveCountAfterSecondEvent = await persistenceActor.readSaveCount()
        let oldEventReplay = try await restoration.applyReorganization(
            eventIdentifier: "header-chain:event-1",
            firstAffectedHeight: 104
        )
        #expect(oldEventReplay == secondEvent)
        #expect(
            await persistenceActor.readSaveCount()
                == saveCountAfterSecondEvent
        )
    }

    @Test("storage persists only public state and enforces exact registration binding")
    func persistPublicStateWithExactBinding() async throws {
        let fixture = try makePositiveFixture()
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [
                .init(transactionHash: fixture.hash, blockHeight: 100),
            ],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let valueActor = ReusablePaymentAddressStorageValueActor()
        let storage = try OpalBase.Storage(
            valueClient: await valueActor.makeValueClient()
        )
        let persistence = await storage
            .makeReusablePaymentAddressStatePersistence(
                identifier: Data("registration-1".utf8)
            )
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistence: persistence,
            restoreStartHeight: 100
        )
        _ = try await restoration.restoreConfirmed(
            upToHeightExclusive: 101,
            windowSize: 1
        )

        let restarted = try await openRestoration(
            transportActor: transportActor,
            persistence: persistence,
            restoreStartHeight: 100
        )
        #expect((await restarted.stateSnapshot).confirmedMatches.count == 1)

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .persistentStateBindingMismatch
        ) {
            _ = try await openRestoration(
                transportActor: transportActor,
                persistence: persistence,
                restoreStartHeight: 99
            )
        }

        let values = await valueActor.readValues()
        #expect(
            values.keys.allSatisfy { !$0.contains("registration-1") }
        )
        let serializedValues = values.values.compactMap {
            String(data: $0, encoding: .utf8)
        }.joined(separator: "\n")
        #expect(
            !serializedValues.contains(
                ReusablePaymentAddressFixtureData.cashCodeMainnet
            )
        )
        #expect(
            !serializedValues.contains(
                try ReusablePaymentAddressFixtureData.makeAddress()
                    .filterPrefix.hexadecimalString
            )
        )
        #expect(
            !serializedValues.contains(
                ReusablePaymentAddressFixtureData.positiveTransactionHex
            )
        )
        let scanSecret = Data(repeating: 0, count: 31) + Data([7])
        let spendSecret = Data(repeating: 0, count: 31) + Data([13])
        #expect(!serializedValues.contains(scanSecret.base64EncodedString()))
        #expect(!serializedValues.contains(spendSecret.base64EncodedString()))
    }

    @Test("partial commit-marker writes restore the previous durable generation")
    func restorePreviousGenerationAfterCommitMarkerFailure() async throws {
        let transportActor = ReusablePaymentAddressRestorationTransportActor()
        let valueActor = ReusablePaymentAddressStorageValueActor()
        let storage = try OpalBase.Storage(
            valueClient: await valueActor.makeValueClient()
        )
        let persistence = await storage
            .makeReusablePaymentAddressStatePersistence(
                identifier: Data("partial-marker-rollback".utf8)
            )
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistence: persistence,
            restoreStartHeight: 100
        )
        await valueActor.failNextCommittedStoreAfterMutation()

        await #expect(throws: OpalBase.Storage.Error.self) {
            _ = try await restoration.restoreConfirmed(
                upToHeightExclusive: 101,
                windowSize: 1
            )
        }

        let inMemoryState = await restoration.stateSnapshot
        #expect(inMemoryState.revision == 1)
        #expect(inMemoryState.nextUnscannedHeight == 100)
        let restarted = try await openRestoration(
            transportActor: transportActor,
            persistence: persistence,
            restoreStartHeight: 100
        )
        let durableState = await restarted.stateSnapshot
        #expect(durableState == inMemoryState)
        #expect(await valueActor.readValues().count == 2)
    }

    @Test("rollback failure retains the still-committed staged generation")
    func retainStagedGenerationAfterCommitMarkerRollbackFailure() async throws {
        let transportActor = ReusablePaymentAddressRestorationTransportActor()
        let valueActor = ReusablePaymentAddressStorageValueActor()
        let storage = try OpalBase.Storage(
            valueClient: await valueActor.makeValueClient()
        )
        let persistence = await storage
            .makeReusablePaymentAddressStatePersistence(
                identifier: Data("partial-marker-retention".utf8)
            )
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistence: persistence,
            restoreStartHeight: 100
        )
        await valueActor.failNextCommittedStoreAfterMutation()
        await valueActor.failNextCommittedStoreBeforeMutation()

        await #expect(throws: OpalBase.Storage.Error.self) {
            _ = try await restoration.restoreConfirmed(
                upToHeightExclusive: 101,
                windowSize: 1
            )
        }

        #expect((await restoration.stateSnapshot).revision == 1)
        let restarted = try await openRestoration(
            transportActor: transportActor,
            persistence: persistence,
            restoreStartHeight: 100
        )
        let durableState = await restarted.stateSnapshot
        #expect(durableState.revision == 2)
        #expect(durableState.nextUnscannedHeight == 101)
        #expect(await valueActor.readValues().count == 3)
    }

    @Test("capability rederivation requires exact current unspent status and preserves tokens")
    func integrateRederivedCapabilityIntoSpending() async throws {
        let fixture = try makePositiveFixture()
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [
                .init(transactionHash: fixture.hash, blockHeight: 100),
            ],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )
        let state = try await restoration.restoreConfirmed(
            upToHeightExclusive: 101,
            windowSize: 1
        )
        let match = try #require(state.confirmedMatches.first)
        let expectedUnspent = OpalBase.Transaction.Output.Unspent(
            output: match.output.transactionOutput,
            previousTransactionHash: match.output.transactionHash,
            previousTransactionOutputIndex: match.output.outputIndex
        )
        let address = try OpalBase.Address(
            script: OpalBase.Script.decode(
                lockingScript: match.output.lockingScript
            ),
            format: .tokenAware,
            network: .mainnet
        )
        let reader = OpalBase.Network.AddressReader(
            AddressReaderClient(
                unspentByAddress: [
                    address.generateString(withPrefix: true): [expectedUnspent],
                ]
            )
        )
        let missingOutputReader = OpalBase.Network.AddressReader(
            AddressReaderClient(unspentByAddress: [:])
        )
        let mismatchedOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: match.output.value + 1,
                lockingScript: match.output.lockingScript,
                tokenData: match.output.tokenData
            ),
            previousTransactionHash: match.output.transactionHash,
            previousTransactionOutputIndex: match.output.outputIndex
        )
        let mismatchedOutputReader = OpalBase.Network.AddressReader(
            AddressReaderClient(
                unspentByAddress: [
                    address.generateString(withPrefix: true): [mismatchedOutput],
                ]
            )
        )

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .unspentOutputNotFound
        ) {
            _ = try await restoration.confirmUnspentOutput(
                for: match.output.outpoint,
                using: missingOutputReader
            )
        }
        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .unspentOutputPayloadMismatch
        ) {
            _ = try await restoration.confirmUnspentOutput(
                for: match.output.outpoint,
                using: mismatchedOutputReader
            )
        }

        let spendable = try await restoration.confirmUnspentOutput(
            for: match.output.outpoint,
            using: reader
        )
        let capability = try await restoration
            .rederiveReceivingCapability(for: match.output.outpoint)
        #expect(capability.publicKey == match.derivation.receivingPublicKey)
        #expect(capability.description.contains("redacted"))

        let recipient = OpalBase.Transaction.Output(
            value: 70_000,
            lockingScript: CashCodeDerivation.makeLockingScript(
                for: try ReusablePaymentAddressFixtureData
                    .makeSenderSigningKey().publicKey
            ),
            tokenData: match.output.tokenData
        )
        let change = OpalBase.Transaction.Output(
            value: 10_000,
            lockingScript: CashCodeDerivation.makeLockingScript(
                for: try ReusablePaymentAddressFixtureData
                    .makeSpendSigningKey().publicKey
            )
        )
        let plan = try await restoration.prepareSpend(
            spending: [spendable],
            recipientOutputs: [recipient],
            changeOutput: change,
            feeRate: 1
        )
        let transaction = try plan.buildTransaction()

        #expect(transaction.outputs.contains { $0.tokenData == match.output.tokenData })
        let qualifying = CashCodeQualifyingInput.collect(from: transaction)
        #expect(qualifying.first?.publicKey == capability.publicKey)

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .cashTokenPreservationRequired
        ) {
            _ = try await restoration.prepareSpend(
                spending: [spendable],
                recipientOutputs: [
                    .init(
                        value: 70_000,
                        lockingScript: recipient.lockingScript
                    ),
                ],
                changeOutput: change,
                feeRate: 1
            )
        }
    }

    @Test("raw transaction hash mismatch aborts before matching or cursor advancement")
    func rejectMismatchedRawTransactionHash() async throws {
        let fixture = try makePositiveFixture()
        let requestedHash = ReusablePaymentAddressFixtureData
            .makeTransactionHash(byte: 0x44)
        let transportActor = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [
                .init(transactionHash: requestedHash, blockHeight: 100),
            ],
            rawTransactions: [requestedHash: fixture.rawTransaction]
        )
        let persistenceActor = ReusablePaymentAddressStatePersistenceActor()
        let restoration = try await openRestoration(
            transportActor: transportActor,
            persistenceActor: persistenceActor,
            restoreStartHeight: 100
        )

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .transactionHashMismatch
        ) {
            _ = try await restoration.restoreConfirmed(
                upToHeightExclusive: 101,
                windowSize: 1
            )
        }
        #expect((await restoration.stateSnapshot).nextUnscannedHeight == 100)
    }

    @Test("restoration rejects invalid windows and conflicting backend references")
    func rejectInvalidWindowsAndReferences() async throws {
        let fixture = try makePositiveFixture()
        let conflictTransport = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [
                .init(transactionHash: fixture.hash, blockHeight: 100),
                .init(transactionHash: fixture.hash, blockHeight: 101),
            ],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let conflictPersistence = ReusablePaymentAddressStatePersistenceActor()
        let conflictRestoration = try await openRestoration(
            transportActor: conflictTransport,
            persistenceActor: conflictPersistence,
            restoreStartHeight: 100
        )

        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error.invalidWindowSize
        ) {
            _ = try await conflictRestoration.restoreConfirmed(
                upToHeightExclusive: 101,
                windowSize: 0
            )
        }
        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error.invalidHeightRange
        ) {
            _ = try await conflictRestoration.restoreConfirmed(
                upToHeightExclusive: 99,
                windowSize: 1
            )
        }
        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .candidateReferenceConflict
        ) {
            _ = try await conflictRestoration.restoreConfirmed(
                upToHeightExclusive: 102,
                windowSize: 2
            )
        }

        let outsideTransport = ReusablePaymentAddressRestorationTransportActor(
            confirmedReferences: [
                .init(transactionHash: fixture.hash, blockHeight: 102),
            ],
            rawTransactions: [fixture.hash: fixture.rawTransaction],
            shouldFilterConfirmedReferences: false
        )
        let outsidePersistence = ReusablePaymentAddressStatePersistenceActor()
        let outsideRestoration = try await openRestoration(
            transportActor: outsideTransport,
            persistenceActor: outsidePersistence,
            restoreStartHeight: 100
        )
        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .candidateOutsideRequestedWindow
        ) {
            _ = try await outsideRestoration.restoreConfirmed(
                upToHeightExclusive: 101,
                windowSize: 1
            )
        }

        let mempoolTransport = ReusablePaymentAddressRestorationTransportActor(
            mempoolReferences: [
                .init(
                    transactionHash: fixture.hash,
                    fee: 1,
                    hasUnconfirmedParent: false
                ),
                .init(
                    transactionHash: fixture.hash,
                    fee: 2,
                    hasUnconfirmedParent: false
                ),
            ],
            rawTransactions: [fixture.hash: fixture.rawTransaction]
        )
        let mempoolPersistence = ReusablePaymentAddressStatePersistenceActor()
        let mempoolRestoration = try await openRestoration(
            transportActor: mempoolTransport,
            persistenceActor: mempoolPersistence,
            restoreStartHeight: 100
        )
        await #expect(
            throws: OpalBase.ReusablePaymentAddress.Error
                .candidateReferenceConflict
        ) {
            _ = try await mempoolRestoration.refreshMempool()
        }
        #expect(
            (await mempoolRestoration.stateSnapshot).mempoolMatches.isEmpty
        )
    }

    private func openRestoration(
        transportActor: ReusablePaymentAddressRestorationTransportActor,
        persistenceActor: ReusablePaymentAddressStatePersistenceActor,
        restoreStartHeight: UInt
    ) async throws -> OpalBase.ReusablePaymentAddress.RestorationActor {
        try await openRestoration(
            transportActor: transportActor,
            persistence: await persistenceActor.makePersistence(),
            restoreStartHeight: restoreStartHeight
        )
    }

    private func openRestoration(
        transportActor: ReusablePaymentAddressRestorationTransportActor,
        persistence: OpalBase.ReusablePaymentAddress.StatePersistence,
        restoreStartHeight: UInt
    ) async throws -> OpalBase.ReusablePaymentAddress.RestorationActor {
        let transport = OpalBase.ReusablePaymentAddress.Transport(
            candidates: .init(
                fetchConfirmedTransactionReferences: { prefix, heights in
                    try await transportActor
                        .fetchConfirmedTransactionReferences(
                            matching: prefix,
                            in: heights
                        )
                },
                fetchMempoolTransactionReferences: { prefix in
                    await transportActor
                        .fetchMempoolTransactionReferences(
                            matching: prefix
                        )
                }
            ),
            transactions: .init(
                fetchRawTransaction: { hash in
                    try await transportActor.fetchRawTransaction(
                        for: hash
                    )
                }
            )
        )
        return try await OpalBase.CashCodeInteractor(
            transport: transport,
            persistence: persistence
        ).openRestoration(
            for: ReusablePaymentAddressFixtureData.makeAddress(),
            keyOrigin: .init(
                scanKeyIdentifier: "wallet/account/rpa-scan",
                spendKeyIdentifier: "wallet/account/rpa-spend"
            ),
            restoreStartHeight: restoreStartHeight,
            scanSigningKey:
                ReusablePaymentAddressFixtureData.makeScanSigningKey(),
            spendSigningKey:
                ReusablePaymentAddressFixtureData.makeSpendSigningKey()
        )
    }

    private func makePositiveFixture(
        lockTime: UInt32 = 0
    ) throws -> (
        hash: OpalBase.Transaction.Hash,
        rawTransaction: Data
    ) {
        let decoded = try ReusablePaymentAddressFixtureData
            .decodeTransaction(
                hexadecimalString: ReusablePaymentAddressFixtureData
                    .positiveTransactionHex
            )
        let transaction: OpalBase.Transaction
        if lockTime == decoded.transaction.lockTime {
            transaction = decoded.transaction
        } else {
            transaction = .init(
                version: decoded.transaction.version,
                inputs: decoded.transaction.inputs,
                outputs: decoded.transaction.outputs,
                lockTime: lockTime
            )
        }
        let rawTransaction = try transaction.encode()
        return (
            OpalBase.Transaction.Hash(
                naturalOrder: OpalCryptoAdapter.hash256(rawTransaction)
            ),
            rawTransaction
        )
    }
}
