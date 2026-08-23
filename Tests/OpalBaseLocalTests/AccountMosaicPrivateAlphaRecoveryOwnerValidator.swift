// AccountMosaicPrivateAlphaRecoveryOwnerValidator.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic private-alpha recovery owner", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaRecoveryOwnerValidator {
    @Test("Private-alpha fresh creation rejects the generic V0 profile before mutation")
    func rejectV0FreshCreation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            usage: .change,
            hashByte: 0x91
        )
        let addressBook = await account.addressBook
        let journalProbe = MosaicAttemptJournalProbeActor()
        let rawAttempt = try await journalProbe.makeFreshAttempt()
        let freshAttempt = OpalBase.Account.MosaicPrivateAlphaJournal
            .FreshAttempt(rawAttempt)
        let binding = try OpalFusion.MosaicPrivateAlphaRuntime.Binding(
            attemptIdentifier: Data(repeating: 0x11, count: 32),
            generationIdentifier: Data(repeating: 0x22, count: 32),
            materialIdentifier: Data(repeating: 0x33, count: 32)
        )
        let fusionAttempt = try OpalFusion.MosaicPrivateAlphaRuntime
            .createFreshAttempt(
                boundTo: binding,
                discoveryEpochStartUnixSeconds: 1_800_000_000
            )

        do {
            _ = try await OpalBase.Account.MosaicPrivateAlphaRuntime
                .createFreshHost(
                    account: account,
                    fusionAttempt: fusionAttempt,
                    walletReservationIdentifier: UUID(),
                    walletGeneration: 7,
                    profile: .opalV0,
                    network: .chipnet,
                    selectedInputs: [selectedInput],
                    outputAmountsSatoshis: [90_000],
                    transactionReader: .init(
                        fetchRawTransaction: { _ in Data() }
                    ),
                    journalAttempt: freshAttempt
                )
            Issue.record("Expected the V0 profile to be rejected")
        } catch let failure as OpalBase.Account.MosaicPrivateAlphaRuntime
            .Failure {
            #expect(failure == .invalidNetworkBinding)
        }

        #expect(await journalProbe.readRecords().isEmpty)
        #expect(
            await addressBook.listSpendableUTXOs().contains(selectedInput)
        )
    }

    @Test("Private-alpha authenticated recovery rejects the generic V0 profile")
    func rejectV0AuthenticatedRecovery() async throws {
        let prepared = try await makeCommittedAttempt()
        let recordsBefore = await prepared.fixture.journalProbe.readRecords()
        let rawRecovery = try await prepared.fixture.journalProbe
            .loadRecovery()
        let recovery = OpalBase.Account.MosaicPrivateAlphaJournal
            .LoadedRecovery(rawRecovery)
        let internalBinding = await prepared.fixture.host.attemptBinding
        let binding = try OpalFusion.MosaicPrivateAlphaRuntime.Binding(
            attemptIdentifier: internalBinding.attemptIdentifier,
            generationIdentifier: internalBinding.generationIdentifier,
            materialIdentifier: internalBinding.materialIdentifier
        )
        let fusionRecovery = try await makeFusionRecovery(binding: binding)

        do {
            _ = try await OpalBase.Account.MosaicPrivateAlphaRuntime
                .loadRecoveryOwner(
                    account: prepared.fixture.account,
                    expectedWalletReservationIdentifier: internalBinding
                        .walletReservationReference.identifier,
                    expectedWalletGeneration: internalBinding
                        .walletReservationReference.generation,
                    transactionReader: .init(
                        fetchRawTransaction: { _ in Data() }
                    ),
                    fusionRecovery: fusionRecovery,
                    journalRecovery: recovery
                )
            Issue.record("Expected V0 recovery to remain unavailable")
        } catch let failure as OpalBase.Account.MosaicPrivateAlphaRuntime
            .Failure {
            #expect(failure == .invalidNetworkBinding)
        }

        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == recordsBefore
        )
    }

    @Test("Recovered committed state rejects wallet outpoint substitution")
    func rejectRecoveredWalletPayloadSubstitution() async throws {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        let substitutedInput = OpalBase.Transaction.Output.Unspent(
            value: prepared.fixture.selectedInput.value + 1,
            lockingScript: prepared.fixture.selectedInput.lockingScript,
            previousTransactionHash: prepared.fixture.selectedInput
                .previousTransactionHash,
            previousTransactionOutputIndex: prepared.fixture.selectedInput
                .previousTransactionOutputIndex
        )
        await prepared.fixture.addressBook.addUTXO(substitutedInput)
        let recordsBefore = await prepared.fixture.journalProbe.readRecords()
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )

        await #expect(
            throws: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner.Failure
                .walletStateMismatch
        ) {
            _ = try await owner.resume()
        }
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(substitutedInput)
        )
        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == recordsBefore
        )
    }

    @Test("Terminal release clears only the exact recovery quarantine owner")
    func releaseOnlyExactRecoveryQuarantineOwner() async throws {
        let prepared = try await makePreparedReservation()
        let overlappingReference = OpalFusion.Host
            .MosaicReservationReference(
                identifier: prepared.lease.reference.identifier,
                generation: prepared.lease.reference.generation + 1
            )
        await prepared.fixture.addressBook.quarantineMosaicInputs(
            [.init(prepared.fixture.selectedInput)],
            ownedBy: overlappingReference
        )
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )

        guard case .terminal(.walletReleased) = try await owner.resume()
        else {
            Issue.record("Expected terminal wallet release")
            return
        }
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(prepared.fixture.selectedInput)
        )

        await prepared.fixture.addressBook.releaseMosaicInputQuarantine(
            ownedBy: overlappingReference
        )
        #expect(
            await prepared.fixture.addressBook.listSpendableUTXOs()
                .contains(prepared.fixture.selectedInput)
        )
    }

    @Test("Prepared reservation crash cuts release only exact wallet effects")
    func recoverPreparedReservationCrashCuts() async throws {
        let crashCuts: [(reserveInput: Bool, reservedOutputCount: Int)] = [
            (false, 0),
            (true, 0),
            (true, 1),
            (true, 2),
        ]

        for crashCut in crashCuts {
            let prepared = try await makePreparedReservation()
            let unrelatedEntry = try #require(
                try await prepared.fixture.addressBook
                    .prepareMosaicReceivingEntries(count: 3).last
            )
            _ = try await prepared.fixture.addressBook
                .reserveMosaicReceivingEntry(unrelatedEntry)

            if crashCut.reserveInput {
                try await prepared.fixture.addressBook.reserveUTXOs(
                    [prepared.fixture.selectedInput]
                )
            }
            for entry in prepared.receivingEntries.prefix(
                crashCut.reservedOutputCount
            ) {
                _ = try await prepared.fixture.addressBook
                    .reserveMosaicReceivingEntry(entry)
            }

            let recovery = try await prepared.fixture.journalProbe
                .loadRecovery()
            let owner = try OpalBase.Account.MosaicPrivateAlphaRecoveryOwner(
                addressBook: prepared.fixture.addressBook,
                recovery: recovery
            )
            let outcome = try await owner.resume()
            guard case .terminal(.walletReleased) = outcome else {
                Issue.record("Expected exact terminal wallet release")
                continue
            }

            #expect(
                await prepared.fixture.addressBook.listSpendableUTXOs()
                    .contains(prepared.fixture.selectedInput)
            )
            for entry in prepared.receivingEntries {
                let recoveredEntry = try #require(
                    await prepared.fixture.addressBook.findEntry(
                        for: entry.address
                    )
                )
                #expect(recoveredEntry.isUsed)
                #expect(!recoveredEntry.isReserved)
            }
            let retainedUnrelatedEntry = try #require(
                await prepared.fixture.addressBook.findEntry(
                    for: unrelatedEntry.address
                )
            )
            #expect(retainedUnrelatedEntry.isUsed)
            #expect(retainedUnrelatedEntry.isReserved)

            let records = await prepared.fixture.journalProbe.readRecords()
            #expect(records.count == 5)
            guard case .releaseIntent = records[2],
                  case .released = records[3],
                  case .terminalDisposition(
                    _, nil, .walletReleased
                  ) = records[4] else {
                Issue.record("Expected persisted release-before-effect recovery")
                continue
            }
        }
    }

    @Test("Terminal erasure authorization is linear under actor reentrancy")
    func authorizeErasureExactlyOnce() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            authorizesErasure: true,
            erasureAuthorizationSuspensionProbe: suspension
        )
        let prepared = try await makePreparedReservation(
            journalProbe: journalProbe
        )
        let recovery = try await journalProbe.loadRecovery()
        let owner = try OpalBase.Account.MosaicPrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            recovery: recovery
        )
        guard case .terminal(.walletReleased) = try await owner.resume()
        else {
            Issue.record("Expected terminal wallet release")
            return
        }

        let firstAuthorization = Task {
            let requirement = try await owner.authorizeJournalErasure()
            try await requirement.confirmOuterCleanup { _ in }
        }
        await suspension.waitUntilSuspended()
        await #expect(
            throws: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner.Failure
                .operationInProgress
        ) {
            _ = try await owner.authorizeJournalErasure()
        }
        await suspension.resume()
        try await firstAuthorization.value

        await #expect(
            throws: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner.Failure
                .erasureAlreadyAuthorized
        ) {
            _ = try await owner.authorizeJournalErasure()
        }
        #expect(await journalProbe.readErasureAuthorizationAttemptCount() == 1)
    }

    @Test("Uncertain committed erasure authorization retries idempotently")
    func retryUncertainErasureAuthorization() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(
            authorizesErasure: true,
            commitThenThrowErasureAuthorizationOnce: true
        )
        let prepared = try await makePreparedReservation(
            journalProbe: journalProbe
        )
        let recovery = try await journalProbe.loadRecovery()
        let owner = try OpalBase.Account.MosaicPrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            recovery: recovery
        )
        _ = try await owner.resume()

        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .erasureAuthorizationFailed
        ) {
            _ = try await owner.authorizeJournalErasure()
        }
        let requirement = try await owner.authorizeJournalErasure()
        try await requirement.confirmOuterCleanup { _ in }
        #expect(await journalProbe.readErasureAuthorizationAttemptCount() == 2)
    }

    @Test("Repeated exact chain observations are durable idempotent reads")
    func reconcileRepeatedChainObservations() async throws {
        let prepared = try await makeAcceptedRecovery()
        guard case .chainReconciliationRequired = try await prepared.owner
            .resume() else {
            Issue.record("Expected chain reconciliation")
            return
        }
        let initialRecordCount = await prepared.fixture.journalProbe
            .readRecords().count

        let unconfirmedClient = makeTransactionClient(
            network: prepared.fixture.network,
            detail: makeDetail(
                exactTransaction: prepared.exactTransaction,
                blockHash: nil,
                confirmations: nil
            )
        )
        _ = try await prepared.owner.reconcileChain(using: unconfirmedClient)
        let afterUnconfirmedCount = await prepared.fixture.journalProbe
            .readRecords().count
        #expect(afterUnconfirmedCount == initialRecordCount + 1)
        _ = try await prepared.owner.reconcileChain(using: unconfirmedClient)
        #expect(
            await prepared.fixture.journalProbe.readRecords().count
                == afterUnconfirmedCount
        )

        let blockHash = Data(repeating: 0x81, count: 32)
        let confirmedClient = makeTransactionClient(
            network: prepared.fixture.network,
            detail: makeDetail(
                exactTransaction: prepared.exactTransaction,
                blockHash: blockHash,
                confirmations: 1
            )
        )
        _ = try await prepared.owner.reconcileChain(using: confirmedClient)
        let afterConfirmedCount = await prepared.fixture.journalProbe
            .readRecords().count
        #expect(afterConfirmedCount == afterUnconfirmedCount + 1)
        _ = try await prepared.owner.reconcileChain(using: confirmedClient)
        #expect(
            await prepared.fixture.journalProbe.readRecords().count
                == afterConfirmedCount
        )

        let advancedClient = makeTransactionClient(
            network: prepared.fixture.network,
            detail: makeDetail(
                exactTransaction: prepared.exactTransaction,
                blockHash: blockHash,
                confirmations: 2
            )
        )
        let advancedOutcome = try await prepared.owner.reconcileChain(
            using: advancedClient
        )
        guard case let .observed(advancedState) = advancedOutcome else {
            Issue.record("Expected confirmation advancement")
            return
        }
        #expect(advancedState.holdReason == nil)
        #expect(
            advancedState.latestObservation?.confirmedIdentity?.confirmations
                == 2
        )

        let absentClient = makeAuthoritativelyAbsentClient(
            network: prepared.fixture.network
        )
        let absentOutcome = try await prepared.owner.reconcileChain(
            using: absentClient
        )
        guard case let .observed(absentState) = absentOutcome else {
            Issue.record("Expected authoritative absence")
            return
        }
        #expect(absentState.holdReason == .transactionDisappeared)
        let afterAbsenceCount = await prepared.fixture.journalProbe
            .readRecords().count
        _ = try await prepared.owner.reconcileChain(using: absentClient)
        #expect(
            await prepared.fixture.journalProbe.readRecords().count
                == afterAbsenceCount
        )
        await #expect(
            throws: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner.Failure
                .terminalDispositionRequired
        ) {
            _ = try await prepared.owner.authorizeChainFinality { _ in true }
        }
    }

    @Test("Chain retreat and block identity changes remain held")
    func holdChainReorganizations() async throws {
        let depthRetreat = try await makeAcceptedRecovery()
        _ = try await depthRetreat.owner.resume()
        let blockHash = Data(repeating: 0x82, count: 32)
        _ = try await depthRetreat.owner.reconcileChain(
            using: makeTransactionClient(
                network: depthRetreat.fixture.network,
                detail: makeDetail(
                    exactTransaction: depthRetreat.exactTransaction,
                    blockHash: blockHash,
                    confirmations: 3
                )
            )
        )
        let retreatOutcome = try await depthRetreat.owner.reconcileChain(
            using: makeTransactionClient(
                network: depthRetreat.fixture.network,
                detail: makeDetail(
                    exactTransaction: depthRetreat.exactTransaction,
                    blockHash: blockHash,
                    confirmations: 2
                )
            )
        )
        guard case let .observed(retreatedState) = retreatOutcome else {
            Issue.record("Expected depth-retreat observation")
            return
        }
        #expect(retreatedState.holdReason == .confirmationDepthRetreated)

        let blockChange = try await makeAcceptedRecovery()
        _ = try await blockChange.owner.resume()
        _ = try await blockChange.owner.reconcileChain(
            using: makeTransactionClient(
                network: blockChange.fixture.network,
                detail: makeDetail(
                    exactTransaction: blockChange.exactTransaction,
                    blockHash: Data(repeating: 0x83, count: 32),
                    confirmations: 2
                )
            )
        )
        let changedOutcome = try await blockChange.owner.reconcileChain(
            using: makeTransactionClient(
                network: blockChange.fixture.network,
                detail: makeDetail(
                    exactTransaction: blockChange.exactTransaction,
                    blockHash: Data(repeating: 0x84, count: 32),
                    confirmations: 1
                )
            )
        )
        guard case let .observed(changedState) = changedOutcome else {
            Issue.record("Expected block-identity change observation")
            return
        }
        #expect(changedState.holdReason == .blockIdentityChanged)
    }

    @Test("Wrong networks and invalid chain metadata never journal")
    func rejectUnattestedChainReads() async throws {
        let prepared = try await makeAcceptedRecovery()
        _ = try await prepared.owner.resume()
        let initialRecords = await prepared.fixture.journalProbe.readRecords()
        let exactDetail = makeDetail(
            exactTransaction: prepared.exactTransaction,
            blockHash: nil,
            confirmations: nil
        )

        await #expect(
            throws: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner.Failure
                .invalidNetworkBinding
        ) {
            _ = try await prepared.owner.reconcileChain(
                using: makeTransactionClient(
                    network: .chipnet,
                    detail: exactDetail
                )
            )
        }
        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == initialRecords
        )

        let malformedConfirmedDetail = makeDetail(
            exactTransaction: prepared.exactTransaction,
            blockHash: nil,
            confirmations: 1
        )
        let outcome = try await prepared.owner.reconcileChain(
            using: makeTransactionClient(
                network: prepared.fixture.network,
                detail: malformedConfirmedDetail
            )
        )
        #expect(outcome == .heldUnknown(.invalidChainMetadata))
        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == initialRecords
        )
    }

    @Test("Latest exact confirmed block authorizes terminal disposition")
    func authorizeLatestConfirmedDisposition() async throws {
        let prepared = try await makeAcceptedRecovery()
        _ = try await prepared.owner.resume()
        let blockHash = Data(repeating: 0x85, count: 32)
        _ = try await prepared.owner.reconcileChain(
            using: makeTransactionClient(
                network: prepared.fixture.network,
                detail: makeDetail(
                    exactTransaction: prepared.exactTransaction,
                    blockHash: blockHash,
                    confirmations: 4
                )
            )
        )

        let disposition = try await prepared.owner.authorizeChainFinality {
            state in
            state.holdReason == nil
                && state.latestObservation?.confirmedIdentity?.blockHash
                    == blockHash
        }
        #expect(
            disposition == .chainFinalized(
                transactionHash: prepared.exactTransaction.hash,
                blockHash: blockHash,
                confirmations: 4
            )
        )
        guard case let .terminal(terminalDisposition) = try await prepared.owner
            .resume() else {
            Issue.record("Expected stable terminal recovery")
            return
        }
        #expect(terminalDisposition == disposition)
    }

    @Test("Recovered commit rejects a missing remote signature before wallet mutation")
    func rejectIncompleteRecoveredCommit() async throws {
        let remote = try MosaicProfileTransactionPolicyFixture
            .makeInputMaterial(seed: 0x52, amountSatoshis: 80_000)
        let probe = MosaicPolicyProbeActor()
        let transactionPolicy = await probe.makeTransactionPolicy(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: transactionPolicy,
            network: .mainnet,
            profile: .opalMainnetAlpha
        )
        let lease = try await fixture.reserve()
        let localInput = try #require(
            lease.participantReservation.inputs.first
        )
        let localOutput = try #require(
            lease.participantReservation.outputs.first
        )
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                remote.transactionInput,
                .init(
                    previousTransactionHash: fixture.selectedInput
                        .previousTransactionHash,
                    previousTransactionOutputIndex: fixture.selectedInput
                        .previousTransactionOutputIndex,
                    unlockingScript: Data()
                ),
            ],
            outputs: [
                .init(
                    value: localOutput.amountSatoshis,
                    lockingScript: Data(localOutput.lockingScriptBytes)
                ),
            ],
            lockTime: 0
        )
        let unsignedBytes = [UInt8](try unsignedTransaction.encode())
        let signingRequest = try OpalFusion.Host
            .MosaicTransactionSigningRequest(
                reservationReference: lease.reference,
                roundIdentifier: fixture.reservationRequest.roundIdentifier,
                transcriptBinding: try MosaicHostFixture
                    .makeTranscriptBinding(
                        profile: fixture.profile,
                        unsignedTransactionBytes: unsignedBytes,
                        discriminator: 0x53
                    ),
                unsignedTransactionBytes: unsignedBytes,
                spentInputs: [remote.participantInput, localInput],
                localInputIndices: [1],
                expectedLocalOutputs: lease.participantReservation.outputs,
                feeRateSatoshisPerByte: fixture.reservationRequest
                    .feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: fixture.reservationRequest
                    .minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: fixture.reservationRequest
                    .maximumExcessFeeSatoshis,
                requiredExcessFeeSatoshis: fixture.reservationRequest
                    .requiredExcessFeeSatoshis,
                transactionProfileIdentifier: fixture.reservationRequest
                    .transactionProfileIdentifier
            )
        let locallySigned = try await fixture.host
            .finalizeMosaicTransaction(for: signingRequest)
        let recovery = try await fixture.journalProbe.loadRecovery()
        let owner = try OpalBase.Account.MosaicPrivateAlphaRecoveryOwner(
            addressBook: fixture.addressBook,
            recovery: recovery
        )
        guard case .locallySignedContinuation = try await owner.resume()
        else {
            Issue.record("Expected exact locally signed continuation")
            return
        }
        let incomplete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: locallySigned.signedFusionTransactionBytes
        )
        let recordsBeforeCommit = await fixture.journalProbe.readRecords()

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .invalidCompleteTransaction
        ) {
            _ = try await owner.commitRecoveredLocallySignedTransaction(
                incomplete
            )
        }
        #expect(
            await fixture.journalProbe.readRecords() == recordsBeforeCommit
        )
        #expect(
            !(await fixture.addressBook.listSpendableUTXOs())
                .contains(fixture.selectedInput)
        )
    }

    @Test("Recovered broadcast approval carries exact review context")
    func provideExactBroadcastApprovalContext() async throws {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        let exactTransaction = try OpalBase.Account.MosaicExactTransaction(
            prepared.complete
        )
        let recovery = try await prepared.fixture.journalProbe.loadRecovery()
        let owner = try OpalBase.Account.MosaicPrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            recovery: recovery
        )
        guard case .broadcastApprovalRequired = try await owner.resume()
        else {
            Issue.record("Expected recovered broadcast approval")
            return
        }
        let approvalProbe = MosaicBroadcastApprovalProbeActor(
            decisions: [.rejected]
        )
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )

        await #expect(
            throws: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner.Failure
                .broadcastNotApproved
        ) {
            _ = try await owner.broadcastRecoveredTransaction(
                securityProfile: MosaicBroadcastApprovalTestSupport
                    .securityProfile,
                using: broadcastProbe.makeClient(
                    testingNetwork: prepared.fixture.network
                ),
                requestApproval: approvalProbe.makeRequester()
            )
        }
        let internalRequest = try #require(
            await approvalProbe.readRequests().first
        )
        let request = try #require(
            OpalBase.Account.MosaicPrivateAlphaRuntime
                .BroadcastApprovalRequest(internalRequest)
        )
        #expect(request.transactionBytes == exactTransaction.bytes)
        #expect(request.transactionHash == exactTransaction.hash)
        #expect(request.transactionSizeBytes == exactTransaction.bytes.count)
        #expect(request.network == prepared.fixture.network)
        #expect(
            request.profile
                == OpalBase.Account.MosaicPrivateAlphaRuntime.Profile(
                    prepared.fixture.profile
                )
        )
        #expect(request.totalInputSatoshis == 100_000)
        #expect(request.totalOutputSatoshis == 99_823)
        #expect(request.feeSatoshis == 177)
        #expect(
            request.feeRateSatoshisPerByte
                == prepared.fixture.reservationRequest
                    .feeRateSatoshisPerByte
        )
        #expect(await broadcastProbe.readBroadcasts().isEmpty)
    }

    private func makeFusionRecovery(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding
    ) async throws -> OpalFusion.MosaicPrivateAlphaRuntime.LoadedRecovery {
        let freshAttempt = try OpalFusion.MosaicPrivateAlphaRuntime
            .createFreshAttempt(
                boundTo: binding,
                discoveryEpochStartUnixSeconds: 1_800_000_000
            )
        let owner = try OpalFusion.MosaicPrivateAlphaRuntime.Owner(
            claiming: freshAttempt
        )
        guard case let .persist(transition) = try await owner.nextStep()
        else {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                .invalidRecoveryState
        }
        return try OpalFusion.MosaicPrivateAlphaRuntime.loadRecovery(
            from: transition.replacementSnapshot,
            expectedBinding: binding
        )
    }

    private func makePreparedReservation(
        journalProbe: MosaicAttemptJournalProbeActor = .init()
    ) async throws -> (
        fixture: MosaicHostFixture,
        lease: OpalFusion.Host.MosaicReservationLease,
        receivingEntries: [OpalBase.Address.Book.Entry]
    ) {
        let outputAmountsSatoshis: [UInt64] = [50_000, 49_789]
        let policy = await MosaicPolicyProbeActor().makeTransactionPolicy(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            network: .mainnet,
            profile: .opalMainnetAlpha,
            outputAmountsSatoshis: outputAmountsSatoshis,
            journalProbe: journalProbe
        )
        let inputEntries = try await fixture.host.validateSelectedInputs()
        let inputRecords = try await fixture.host.makeReservedInputRecords(
            entries: inputEntries
        )
        let receivingEntries = try await fixture.addressBook
            .prepareMosaicReceivingEntries(
                count: outputAmountsSatoshis.count
            )
        let reference = await fixture.host.attemptBinding
            .walletReservationReference
        let lease = try OpalFusion.Host.MosaicReservationLease(
            reference: reference,
            expiresAt: fixture.reservationRequest.expiresAt,
            participantReservation: .init(
                inputs: inputRecords.map(\.participantInput),
                outputs: zip(
                    receivingEntries,
                    outputAmountsSatoshis
                ).map { entry, amountSatoshis in
                    .init(
                        lockingScriptBytes: [UInt8](
                            entry.address.lockingScript.data
                        ),
                        amountSatoshis: amountSatoshis
                    )
                }
            )
        )
        let journal = await fixture.host.attemptJournal
        try await journal.append(
            .reservationPrepared(
                request: fixture.reservationRequest,
                selectedInputs: [
                    .init(fixture.selectedInput),
                ],
                outputAmountsSatoshis: outputAmountsSatoshis,
                lease: lease
            )
        )
        return (fixture, lease, receivingEntries)
    }

    private func makeAcceptedRecovery() async throws -> (
        owner: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner,
        fixture: MosaicHostFixture,
        exactTransaction: OpalBase.Account.MosaicExactTransaction
    ) {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        let exactTransaction = try OpalBase.Account.MosaicExactTransaction(
            prepared.complete
        )
        try await prepared.candidate.journal.append(
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        try await prepared.candidate.journal.append(
            .broadcastIntent(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        try await prepared.candidate.journal.append(
            .broadcastAccepted(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                transactionHash: exactTransaction.hash
            )
        )
        let recovery = try await prepared.fixture.journalProbe.loadRecovery()
        return (
            try OpalBase.Account.MosaicPrivateAlphaRecoveryOwner(
                addressBook: prepared.fixture.addressBook,
                recovery: recovery
            ),
            prepared.fixture,
            exactTransaction
        )
    }

    private func makeDetail(
        exactTransaction: OpalBase.Account.MosaicExactTransaction,
        blockHash: Data?,
        confirmations: UInt32?
    ) -> OpalBase.Transaction.Detail {
        .init(
            transaction: exactTransaction.transaction,
            blockHash: blockHash,
            blockTime: blockHash == nil ? nil : 1_900_000_000,
            confirmations: confirmations,
            hash: exactTransaction.hash,
            rawTransactionData: exactTransaction.bytes,
            size: UInt32(exactTransaction.bytes.count),
            time: nil
        )
    }

    private func makeTransactionClient(
        network: OpalBase.Network.Environment,
        detail: OpalBase.Transaction.Detail
    ) -> OpalBase.Account.MosaicNetworkAttestedTransactionClient {
        .init(
            testingNetwork: network,
            transactionClient: .init(
                broadcastTransaction: { _ in
                    detail.hash.reverseOrder.hexadecimalString
                },
                fetchConfirmations: { _ in
                    detail.confirmations.map(UInt.init)
                },
                fetchConfirmationStatus: { transactionHash in
                    .init(
                        transactionHash: transactionHash,
                        transactionHeight: nil,
                        tipHeight: 0,
                        confirmations: detail.confirmations.map(UInt.init)
                    )
                }
            ),
            fetchFreshDetailedTransaction: { _ in detail }
        )
    }

    private func makeAuthoritativelyAbsentClient(
        network: OpalBase.Network.Environment
    ) -> OpalBase.Account.MosaicNetworkAttestedTransactionClient {
        .init(
            testingNetwork: network,
            transactionClient: .init(
                broadcastTransaction: { _ in String(repeating: "0", count: 64) },
                fetchConfirmations: { _ in nil },
                fetchConfirmationStatus: { transactionHash in
                    .init(
                        transactionHash: transactionHash,
                        transactionHeight: nil,
                        tipHeight: 0,
                        confirmations: nil
                    )
                }
            ),
            fetchFreshDetailedTransaction: { _ in
                throw OpalBase.Network.Error(
                    reason: .server(code: -5),
                    message: "Transaction is authoritatively absent."
                )
            }
        )
    }
}
#endif
