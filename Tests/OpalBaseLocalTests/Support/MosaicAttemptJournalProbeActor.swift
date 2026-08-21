// MosaicAttemptJournalProbeActor.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) @testable import OpalBase

actor MosaicAttemptJournalProbeActor {
    private static let authenticationKeyData = Data(repeating: 0x7a, count: 32)

    private let authenticationKey:
        OpalBase.Account.MosaicPrivateAlphaJournal.JournalKey
    private let scope: OpalBase.Account.MosaicAttemptJournalCodec.Scope
    private let codec: OpalBase.Account.MosaicAttemptJournalCodec
    private var persistedEnvelope: Data?
    private var records: [OpalBase.Account.MosaicAttemptJournal.Record] = []
    private var appendAttemptIndex = 0
    private var failingAppendIndices: Set<Int>
    private let suspendedAppendIndex: Int?
    private let suspensionProbe: MosaicOperationSuspensionProbeActor?
    private let cancellationSensitiveAppendIndices: Set<Int>
    private let authorizesErasure: Bool
    private let erasureAuthorizationSuspensionProbe:
        MosaicOperationSuspensionProbeActor?
    private var commitThenThrowErasureAuthorizationOnce: Bool
    private var erasureAuthorizationAttemptCount = 0
    private var authorizedCleanupContext:
        OpalBase.Account.MosaicPrivateAlphaJournal.CleanupContext?
    private var cancellationObservations: [Int: Bool] = [:]
    private var cancellationObservationWaiters: [
        Int: [CheckedContinuation<Bool, Never>]
    ] = [:]

    init(
        failingAppendIndices: Set<Int> = [],
        suspendedAppendIndex: Int? = nil,
        suspensionProbe: MosaicOperationSuspensionProbeActor? = nil,
        cancellationSensitiveAppendIndices: Set<Int> = [],
        authorizesErasure: Bool = false,
        erasureAuthorizationSuspensionProbe:
            MosaicOperationSuspensionProbeActor? = nil,
        commitThenThrowErasureAuthorizationOnce: Bool = false
    ) {
        let authenticationKey = try! OpalBase.Account
            .MosaicPrivateAlphaJournal.JournalKey(
                fieldDerivedKeyMaterial: Self.authenticationKeyData
            )
        let scope = OpalBase.Account.MosaicAttemptJournalCodec.Scope(
            walletIdentifier: UUID(),
            journalIdentifier: UUID()
        )
        self.authenticationKey = authenticationKey
        self.scope = scope
        codec = try! .init(
            authenticationKey: authenticationKey,
            scope: scope
        )
        self.failingAppendIndices = failingAppendIndices
        self.suspendedAppendIndex = suspendedAppendIndex
        self.suspensionProbe = suspensionProbe
        self.cancellationSensitiveAppendIndices = cancellationSensitiveAppendIndices
        self.authorizesErasure = authorizesErasure
        self.erasureAuthorizationSuspensionProbe =
            erasureAuthorizationSuspensionProbe
        self.commitThenThrowErasureAuthorizationOnce =
            commitThenThrowErasureAuthorizationOnce
    }

    static func makeAuthenticatedForPrivateAlphaTesting() async throws
        -> MosaicAttemptJournalProbeActor {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        return prepared.fixture.journalProbe
    }

    private init(
        scope: OpalBase.Account.MosaicAttemptJournalCodec.Scope,
        persistedEnvelope: Data
    ) throws {
        let authenticationKey = try OpalBase.Account
            .MosaicPrivateAlphaJournal.JournalKey(
                fieldDerivedKeyMaterial: Self.authenticationKeyData
            )
        let codec = try OpalBase.Account.MosaicAttemptJournalCodec(
            authenticationKey: authenticationKey,
            scope: scope
        )
        let records = try codec.open(persistedEnvelope)

        self.authenticationKey = authenticationKey
        self.scope = scope
        self.codec = codec
        self.persistedEnvelope = persistedEnvelope
        self.records = records
        failingAppendIndices = []
        suspendedAppendIndex = nil
        suspensionProbe = nil
        cancellationSensitiveAppendIndices = []
        authorizesErasure = false
        erasureAuthorizationSuspensionProbe = nil
        commitThenThrowErasureAuthorizationOnce = false
    }

    func makeFreshAttempt() async throws
        -> OpalBase.Account.MosaicAttemptJournalStore.FreshAttempt {
        let freshAttempt = try await OpalBase.Account.MosaicAttemptJournalStore
            .createNew(
                authenticationKey: authenticationKey,
                scope: scope,
                persistence: makePersistence()
            )
        return freshAttempt
    }

    func makeFreshJournalForTesting() async throws
        -> OpalBase.Account.MosaicAttemptJournal {
        let freshAttempt = try await makeFreshAttempt()
        return freshAttempt.claimJournal()
    }

    func makeBoundJournalForTesting(
        _ binding: OpalBase.Account.MosaicAttemptBinding
    ) async throws -> OpalBase.Account.MosaicAttemptJournal {
        let journal = try await makeFreshJournalForTesting()
        try await journal.append(.attemptBinding(binding))
        return journal
    }

    func loadRecovery() async throws
        -> OpalBase.Account.MosaicAttemptJournalStore.LoadedRecovery {
        try await OpalBase.Account.MosaicAttemptJournalStore.loadExisting(
            authenticationKey: authenticationKey,
            scope: scope,
            persistence: makePersistence()
        )
    }

    func readRecords() -> [OpalBase.Account.MosaicAttemptJournal.Record] {
        records
    }

    func readPersistedEnvelope() -> Data? {
        persistedEnvelope
    }

    func readFieldDerivedJournalKey()
        -> OpalBase.Account.MosaicPrivateAlphaJournal.JournalKey {
        authenticationKey
    }

    func readErasureAuthorizationAttemptCount() -> Int {
        erasureAuthorizationAttemptCount
    }

    func readJournalScopeIdentifiers() -> (
        walletIdentifier: UUID,
        journalIdentifier: UUID
    ) {
        (
            scope.walletIdentifier,
            scope.journalIdentifier
        )
    }

    func readApplicationScope()
        -> OpalBase.Account.MosaicPrivateAlphaJournal.Scope {
        .init(
            walletIdentifier: scope.walletIdentifier,
            journalIdentifier: scope.journalIdentifier
        )
    }

    nonisolated func makeApplicationPersistence()
        -> OpalBase.Account.MosaicPrivateAlphaJournal.Persistence {
        .init(
            loadJournalState: { await self.loadState() },
            createEnvelopeDurably: { envelope in
                try await self.createDurably(envelope)
            },
            compareAndReplaceEnvelopeDurably: { expected, replacement in
                try await self.compareAndReplaceDurably(
                    expected: expected,
                    replacement: replacement
                )
            },
            compareAndAuthorizeJournalErasureDurably: { expected, context in
                try await self.compareAndAuthorizeErasureDurably(
                    expected: expected,
                    context: context
                )
            }
        )
    }

    /// Reconstructs a process-equivalent persistence owner from durable bytes and key scope only.
    func makeRestartedProbe() throws -> MosaicAttemptJournalProbeActor {
        guard let persistedEnvelope else {
            throw OpalBase.Account.MosaicAttemptJournalStore.Failure.notFound
        }
        return try .init(
            scope: scope,
            persistedEnvelope: persistedEnvelope
        )
    }

    func waitForCancellationObservation(atAppendIndex index: Int) async -> Bool {
        if let observation = cancellationObservations[index] {
            return observation
        }
        return await withCheckedContinuation { continuation in
            cancellationObservationWaiters[index, default: []].append(continuation)
        }
    }

    private nonisolated func makePersistence()
        -> OpalBase.Account.MosaicAttemptJournalStore.Persistence {
        .init(
            loadState: { await self.loadState() },
            createDurably: { envelope in
                try await self.createDurably(envelope)
            },
            compareAndReplaceDurably: { expected, replacement in
                try await self.compareAndReplaceDurably(
                    expected: expected,
                    replacement: replacement
                )
            },
            compareAndAuthorizeErasureDurably: { expected, context in
                try await self.compareAndAuthorizeErasureDurably(
                    expected: expected,
                    context: context
                )
            }
        )
    }

    private func loadState()
        -> OpalBase.Account.MosaicPrivateAlphaJournal.PersistedState {
        if let authorizedCleanupContext {
            return .journalErasureAuthorized(authorizedCleanupContext)
        }
        guard let persistedEnvelope else {
            return .absent
        }
        return .encryptedEnvelope(persistedEnvelope)
    }

    private func createDurably(_ envelope: Data) throws -> Bool {
        guard persistedEnvelope == nil else {
            return false
        }
        let decoded = try codec.open(envelope)
        guard decoded.isEmpty else {
            throw MosaicAttemptJournalProbeFailure.scripted
        }
        persistedEnvelope = envelope
        records = decoded
        return true
    }

    private func compareAndReplaceDurably(
        expected: Data,
        replacement: Data
    ) async throws -> Bool {
        let decoded = try codec.open(replacement)
        if decoded.count == 1,
           case .attemptBinding = decoded[0] {
            guard persistedEnvelope == expected else { return false }
            persistedEnvelope = replacement
            records = decoded
            return true
        }
        let index = appendAttemptIndex
        appendAttemptIndex += 1
        if index == suspendedAppendIndex, let suspensionProbe {
            await suspensionProbe.suspend()
        }
        let wasCancelled = Task.isCancelled
        cancellationObservations[index] = wasCancelled
        cancellationObservationWaiters.removeValue(forKey: index)?.forEach {
            $0.resume(returning: wasCancelled)
        }
        if cancellationSensitiveAppendIndices.contains(index) {
            try Task.checkCancellation()
        }
        if failingAppendIndices.remove(index) != nil {
            throw MosaicAttemptJournalProbeFailure.scripted
        }
        guard persistedEnvelope == expected else {
            return false
        }
        persistedEnvelope = replacement
        records = decoded
        return true
    }

    private func compareAndAuthorizeErasureDurably(
        expected: Data,
        context: OpalBase.Account.MosaicPrivateAlphaJournal.CleanupContext
    ) async throws -> Bool {
        let index = erasureAuthorizationAttemptCount
        erasureAuthorizationAttemptCount += 1
        if index == 0, let erasureAuthorizationSuspensionProbe {
            await erasureAuthorizationSuspensionProbe.suspend()
        }
        guard authorizesErasure else { return false }
        if let authorizedCleanupContext {
            return authorizedCleanupContext == context
        }
        guard persistedEnvelope == expected else { return false }
        authorizedCleanupContext = context
        if commitThenThrowErasureAuthorizationOnce {
            commitThenThrowErasureAuthorizationOnce = false
            throw MosaicAttemptJournalProbeFailure.scripted
        }
        return true
    }

}
#endif
