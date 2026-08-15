// OpalBase+Account+MosaicAttemptJournal.swift

#if os(macOS)
import CryptoKit
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Stateless append access to one authenticated Mosaic attempt journal store.
    ///
    /// Records contain wallet-private material. The store seals the complete versioned snapshot before
    /// an app-owned backend atomically and durably replaces it. Key persistence and storage location
    /// remain app-owned.
    struct MosaicAttemptJournal: Sendable {
        fileprivate let store: MosaicAttemptJournalStore

        fileprivate init(store: MosaicAttemptJournalStore) {
            self.store = store
        }

        func append(_ record: Record) async throws {
            try await store.append(record)
        }

        func authorizeTerminalDisposition() async throws
            -> MosaicAttemptJournalErasureAuthorization {
            try await store.authorizeTerminalDisposition()
        }
    }

    /// The sole mutable owner of one journal's authenticated whole-snapshot state.
    actor MosaicAttemptJournalStore {
        /// App-owned durable persistence operations.
        ///
        /// `loadState` must report a durable erasure authorization instead of its retained envelope.
        /// `createDurably` must be exclusive and return `false` without replacing an existing value or
        /// erasure authorization.
        /// `compareAndReplaceDurably` must atomically compare the exact current envelope, synchronize the
        /// replacement, rename it over that envelope, and synchronize the containing directory before
        /// returning `true`. `compareAndAuthorizeErasureDurably` must atomically compare the exact current
        /// envelope and durably commit a terminal marker bound to that envelope's SHA-256 and scope before
        /// returning `true`; it must not report physical ciphertext or key-material cleanup. The exact same
        /// context must return `true` idempotently when its marker is already authoritative, including after
        /// an earlier commit-then-throw or commit-then-cancel outcome. A mismatched context returns `false`
        /// without mutation. A thrown replacement must leave the prior envelope authoritative, while a
        /// thrown authorization is outcome-uncertain and must be resolved by retry or `loadState` read-back.
        /// Rollback, unexpected deletion detection, and outer cleanup remain app-owned.
        struct Persistence: Sendable {
            let loadState: @Sendable () async throws
                -> MosaicPrivateAlphaJournal.PersistedState
            let createDurably: @Sendable (Data) async throws -> Bool
            let compareAndReplaceDurably: @Sendable (
                _ expected: Data,
                _ replacement: Data
            ) async throws -> Bool
            let compareAndAuthorizeErasureDurably: @Sendable (
                _ expectedEnvelope: Data,
                _ context: MosaicPrivateAlphaJournal.CleanupContext
            ) async throws -> Bool

            init(
                loadState: @escaping @Sendable () async throws
                    -> MosaicPrivateAlphaJournal.PersistedState,
                createDurably: @escaping @Sendable (Data) async throws -> Bool,
                compareAndReplaceDurably: @escaping @Sendable (
                    _ expected: Data,
                    _ replacement: Data
                ) async throws -> Bool,
                compareAndAuthorizeErasureDurably: @escaping @Sendable (
                    _ expectedEnvelope: Data,
                    _ context: MosaicPrivateAlphaJournal.CleanupContext
                ) async throws -> Bool
            ) {
                self.loadState = loadState
                self.createDurably = createDurably
                self.compareAndReplaceDurably = compareAndReplaceDurably
                self.compareAndAuthorizeErasureDurably =
                    compareAndAuthorizeErasureDurably
            }
        }

        enum Failure: Swift.Error, Sendable, Equatable {
            case notFound
            case alreadyExists
            case creationUncertain
            case loadFailed
            case createFailed
            case replaceFailed
            case erasureAuthorizationFailed
            case staleSnapshot
            case erasureNotAuthorized
            case cleanupRequired
            case journalErased
            case codec(MosaicAttemptJournalCodec.Failure)
            case invalidJournal(MosaicAttemptRecoveryPlanner.Error)
        }

        /// One-use proof that an empty encrypted journal was exclusively created for a fresh attempt.
        struct FreshAttempt: ~Copyable, Sendable {
            fileprivate let store: MosaicAttemptJournalStore

            fileprivate init(store: MosaicAttemptJournalStore) {
                self.store = store
            }

            consuming func claimJournal() -> MosaicAttemptJournal {
                .init(store: store)
            }

            consuming func authorizeAbandonment() async throws
                -> MosaicAttemptJournalErasureAuthorization {
                try await store.authorizeFreshAttemptAbandonment()
            }
        }

        /// One-use authenticated restart state. It cannot create a fresh wallet host.
        struct LoadedRecovery: ~Copyable, Sendable {
            fileprivate let store: MosaicAttemptJournalStore
            fileprivate let binding: MosaicAttemptBinding
            fileprivate let records: [MosaicAttemptJournal.Record]
            fileprivate let plan: MosaicAttemptRecoveryPlanner.Plan

            fileprivate init(
                store: MosaicAttemptJournalStore,
                binding: MosaicAttemptBinding,
                records: [MosaicAttemptJournal.Record],
                plan: MosaicAttemptRecoveryPlanner.Plan
            ) {
                self.store = store
                self.binding = binding
                self.records = records
                self.plan = plan
            }

            consuming func claim() -> RecoveryState {
                .init(
                    journal: .init(store: store),
                    binding: binding,
                    records: records,
                    plan: plan
                )
            }
        }

        struct RecoveryState: Sendable {
            let journal: MosaicAttemptJournal
            let binding: MosaicAttemptBinding
            let records: [MosaicAttemptJournal.Record]
            let plan: MosaicAttemptRecoveryPlanner.Plan
        }

        private var codec: MosaicAttemptJournalCodec?
        private var persistence: Persistence?
        private var records: [MosaicAttemptJournal.Record]
        private var currentEnvelope: Data?
        private let scope: MosaicAttemptJournalCodec.Scope

        private init(
            codec: MosaicAttemptJournalCodec,
            persistence: Persistence,
            records: [MosaicAttemptJournal.Record],
            currentEnvelope: Data,
            scope: MosaicAttemptJournalCodec.Scope
        ) {
            self.codec = codec
            self.persistence = persistence
            self.records = records
            self.currentEnvelope = currentEnvelope
            self.scope = scope
        }

        static func createNew(
            authenticationKey: SymmetricKey,
            scope: MosaicAttemptJournalCodec.Scope,
            persistence: Persistence
        ) async throws -> FreshAttempt {
            let codec: MosaicAttemptJournalCodec
            let initialEnvelope: Data
            do {
                codec = try .init(
                    authenticationKey: authenticationKey,
                    scope: scope
                )
                initialEnvelope = try codec.seal(records: [])
            } catch let failure as MosaicAttemptJournalCodec.Failure {
                throw Failure.codec(failure)
            }

            let created: Bool
            do {
                created = try await persistence.createDurably(initialEnvelope)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure.createFailed
            }
            guard created else {
                throw Failure.alreadyExists
            }

            return .init(
                store: .init(
                    codec: codec,
                    persistence: persistence,
                    records: [],
                    currentEnvelope: initialEnvelope,
                    scope: scope
                )
            )
        }

        static func loadExisting(
            authenticationKey: SymmetricKey,
            scope: MosaicAttemptJournalCodec.Scope,
            persistence: Persistence
        ) async throws -> LoadedRecovery {
            let outcome = try await authenticateExisting(
                authenticationKey: authenticationKey,
                scope: scope,
                persistence: persistence
            )
            switch consume outcome {
            case .abandonedFreshAttempt:
                throw Failure.creationUncertain
            case let .loadedRecovery(recovery):
                return recovery
            }
        }

        static func authenticateExisting(
            authenticationKey: SymmetricKey,
            scope: MosaicAttemptJournalCodec.Scope,
            persistence: Persistence
        ) async throws -> MosaicAttemptJournalAuthenticationOutcome {
            let persistedState: MosaicPrivateAlphaJournal.PersistedState
            do {
                persistedState = try await persistence.loadState()
            } catch let failure as Failure {
                throw failure
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure.loadFailed
            }

            let envelope: Data
            switch persistedState {
            case .absent:
                throw Failure.notFound
            case let .encryptedEnvelope(loadedEnvelope):
                envelope = loadedEnvelope
            case let .journalErasureAuthorized(context):
                guard context.scope.journalScope == scope else {
                    throw Failure.staleSnapshot
                }
                throw Failure.cleanupRequired
            }

            let codec: MosaicAttemptJournalCodec
            let records: [MosaicAttemptJournal.Record]
            do {
                codec = try .init(
                    authenticationKey: authenticationKey,
                    scope: scope
                )
                records = try codec.open(envelope)
            } catch let failure as MosaicAttemptJournalCodec.Failure {
                throw Failure.codec(failure)
            }

            let store = MosaicAttemptJournalStore(
                codec: codec,
                persistence: persistence,
                records: records,
                currentEnvelope: envelope,
                scope: scope
            )
            guard !records.isEmpty else {
                return .abandonedFreshAttempt(
                    .init(
                        store: store,
                        expectedEnvelopeSHA256: Data(
                            SHA256.hash(data: envelope)
                        )
                    )
                )
            }

            let plan: MosaicAttemptRecoveryPlanner.Plan
            let binding: MosaicAttemptBinding
            do {
                plan = try MosaicAttemptRecoveryPlanner.plan(for: records)
                guard let resolvedBinding = try MosaicAttemptRecoveryPlanner
                    .binding(for: records) else {
                    throw MosaicAttemptRecoveryPlanner.Error
                        .attemptBindingMismatch
                }
                binding = resolvedBinding
            } catch let error as MosaicAttemptRecoveryPlanner.Error {
                throw Failure.invalidJournal(error)
            }

            return .loadedRecovery(
                .init(
                    store: store,
                    binding: binding,
                    records: records,
                    plan: plan
                )
            )
        }

        fileprivate func append(
            _ record: MosaicAttemptJournal.Record
        ) async throws {
            guard let codec, let persistence, let currentEnvelope else {
                throw Failure.journalErased
            }
            let candidateRecords = records + [record]
            do {
                _ = try MosaicAttemptRecoveryPlanner.plan(for: candidateRecords)
            } catch let error as MosaicAttemptRecoveryPlanner.Error {
                throw Failure.invalidJournal(error)
            }

            let envelope: Data
            do {
                envelope = try codec.seal(records: candidateRecords)
            } catch let failure as MosaicAttemptJournalCodec.Failure {
                throw Failure.codec(failure)
            }

            let replaced: Bool
            do {
                replaced = try await persistence.compareAndReplaceDurably(
                    currentEnvelope,
                    envelope
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure.replaceFailed
            }
            guard replaced else {
                throw Failure.staleSnapshot
            }
            records = candidateRecords
            self.currentEnvelope = envelope
        }

        fileprivate func authorizeFreshAttemptAbandonment() throws
            -> MosaicAttemptJournalErasureAuthorization {
            guard records.isEmpty,
                  persistence != nil,
                  let currentEnvelope else {
                throw Failure.erasureNotAuthorized
            }
            return .init(
                store: self,
                expectedEnvelopeSHA256: Data(
                    SHA256.hash(data: currentEnvelope)
                )
            )
        }

        fileprivate func authorizeTerminalDisposition() throws
            -> MosaicAttemptJournalErasureAuthorization {
            guard let currentEnvelope,
                  persistence != nil,
                  case .terminal = try MosaicAttemptRecoveryPlanner.plan(
                    for: records
                  ) else {
                throw Failure.erasureNotAuthorized
            }
            return .init(
                store: self,
                expectedEnvelopeSHA256: Data(
                    SHA256.hash(data: currentEnvelope)
                )
            )
        }

        func authorizeJournalErasure(
            expectedEnvelopeSHA256: Data
        ) async throws
            -> MosaicAttemptJournalCleanupRequirement {
            guard let currentEnvelope,
                  Data(SHA256.hash(data: currentEnvelope))
                    == expectedEnvelopeSHA256 else {
                throw Failure.erasureNotAuthorized
            }
            if !records.isEmpty {
                guard case .terminal = try MosaicAttemptRecoveryPlanner.plan(
                    for: records
                ) else {
                    throw Failure.erasureNotAuthorized
                }
            }
            guard let persistence else {
                throw Failure.journalErased
            }

            let context = MosaicPrivateAlphaJournal.CleanupContext(
                validatedScope: .init(journalScope: scope),
                expectedEnvelopeSHA256: expectedEnvelopeSHA256
            )
            let authorized: Bool
            do {
                authorized = try await persistence
                    .compareAndAuthorizeErasureDurably(
                        currentEnvelope,
                        context
                    )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure.erasureAuthorizationFailed
            }
            guard authorized else {
                throw Failure.staleSnapshot
            }

            records.removeAll(keepingCapacity: false)
            self.currentEnvelope = nil
            codec = nil
            self.persistence = nil
            return .init(context: context)
        }

        static func loadAuthorizedJournalCleanup(
            scope: MosaicAttemptJournalCodec.Scope,
            persistence: Persistence
        ) async throws -> MosaicAttemptJournalCleanupRequirement? {
            let persistedState: MosaicPrivateAlphaJournal.PersistedState
            do {
                persistedState = try await persistence.loadState()
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure.loadFailed
            }

            switch persistedState {
            case .absent, .encryptedEnvelope:
                return nil
            case let .journalErasureAuthorized(context):
                guard context.scope.journalScope == scope else {
                    throw Failure.staleSnapshot
                }
                return .init(context: context)
            }
        }
    }
}
#endif
