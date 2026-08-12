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
    }

    /// The sole mutable owner of one journal's authenticated whole-snapshot state.
    actor MosaicAttemptJournalStore {
        /// App-owned durable persistence operations.
        ///
        /// `createDurably` must be exclusive and return `false` without replacing an existing value.
        /// `compareAndReplaceDurably` must atomically compare the exact current envelope, synchronize the
        /// replacement, rename it over that envelope, and synchronize the containing directory before
        /// returning `true`. A mismatch returns `false` without mutation, and a thrown replacement leaves
        /// the prior snapshot authoritative. Rollback and deletion detection remain app-owned.
        struct Persistence: Sendable {
            let load: @Sendable () async throws -> Data?
            let createDurably: @Sendable (Data) async throws -> Bool
            let compareAndReplaceDurably: @Sendable (
                _ expected: Data,
                _ replacement: Data
            ) async throws -> Bool

            init(
                load: @escaping @Sendable () async throws -> Data?,
                createDurably: @escaping @Sendable (Data) async throws -> Bool,
                compareAndReplaceDurably: @escaping @Sendable (
                    _ expected: Data,
                    _ replacement: Data
                ) async throws -> Bool
            ) {
                self.load = load
                self.createDurably = createDurably
                self.compareAndReplaceDurably = compareAndReplaceDurably
            }
        }

        enum Failure: Swift.Error, Sendable, Equatable {
            case notFound
            case alreadyExists
            case creationUncertain
            case loadFailed
            case createFailed
            case replaceFailed
            case staleSnapshot
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
        }

        /// One-use authenticated restart state. It cannot create a fresh wallet host.
        struct LoadedRecovery: ~Copyable, Sendable {
            fileprivate let store: MosaicAttemptJournalStore
            fileprivate let records: [MosaicAttemptJournal.Record]
            fileprivate let plan: MosaicAttemptRecoveryPlanner.Plan

            fileprivate init(
                store: MosaicAttemptJournalStore,
                records: [MosaicAttemptJournal.Record],
                plan: MosaicAttemptRecoveryPlanner.Plan
            ) {
                self.store = store
                self.records = records
                self.plan = plan
            }

            consuming func claim() -> RecoveryState {
                .init(
                    journal: .init(store: store),
                    records: records,
                    plan: plan
                )
            }
        }

        struct RecoveryState: Sendable {
            let journal: MosaicAttemptJournal
            let records: [MosaicAttemptJournal.Record]
            let plan: MosaicAttemptRecoveryPlanner.Plan
        }

        private let codec: MosaicAttemptJournalCodec
        private let persistence: Persistence
        private var records: [MosaicAttemptJournal.Record]
        private var currentEnvelope: Data

        private init(
            codec: MosaicAttemptJournalCodec,
            persistence: Persistence,
            records: [MosaicAttemptJournal.Record],
            currentEnvelope: Data
        ) {
            self.codec = codec
            self.persistence = persistence
            self.records = records
            self.currentEnvelope = currentEnvelope
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
                    currentEnvelope: initialEnvelope
                )
            )
        }

        static func loadExisting(
            authenticationKey: SymmetricKey,
            scope: MosaicAttemptJournalCodec.Scope,
            persistence: Persistence
        ) async throws -> LoadedRecovery {
            let envelope: Data
            do {
                guard let loaded = try await persistence.load() else {
                    throw Failure.notFound
                }
                envelope = loaded
            } catch let failure as Failure {
                throw failure
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure.loadFailed
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
            guard !records.isEmpty else {
                throw Failure.creationUncertain
            }

            let plan: MosaicAttemptRecoveryPlanner.Plan
            do {
                plan = try MosaicAttemptRecoveryPlanner.plan(for: records)
            } catch let error as MosaicAttemptRecoveryPlanner.Error {
                throw Failure.invalidJournal(error)
            }

            let store = MosaicAttemptJournalStore(
                codec: codec,
                persistence: persistence,
                records: records,
                currentEnvelope: envelope
            )
            return .init(store: store, records: records, plan: plan)
        }

        fileprivate func append(
            _ record: MosaicAttemptJournal.Record
        ) async throws {
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
            currentEnvelope = envelope
        }
    }
}
#endif
