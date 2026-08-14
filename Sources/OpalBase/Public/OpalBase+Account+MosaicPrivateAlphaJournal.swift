// OpalBase+Account+MosaicPrivateAlphaJournal.swift

#if os(macOS)
import CryptoKit

extension OpalBase.Account {
    /// Deliberately private-alpha access to app-owned Mosaic journal persistence.
    ///
    /// This SPI does not enable a public Mosaic session. The app remains responsible for deriving and
    /// retaining the field-specific key, supplying durable storage, and detecting rollback or deletion.
    @_spi(MosaicPrivateAlpha)
    public enum MosaicPrivateAlphaJournal {
        /// Exclusively creates the authenticated empty journal for a new attempt.
        ///
        /// The key must be the 256-bit field-derived key for this scope. Its provenance cannot be verified
        /// by OpalBase, so callers must not pass a wallet master key or other reusable secret directly.
        @_spi(MosaicPrivateAlpha)
        public static func createFreshAttempt(
            fieldDerivedJournalKey: SymmetricKey,
            scope: Scope,
            persistence: Persistence
        ) async throws -> FreshAttempt {
            do {
                let attempt = try await MosaicAttemptJournalStore.createNew(
                    authenticationKey: fieldDerivedJournalKey,
                    scope: scope.journalScope,
                    persistence: persistence.journalPersistence
                )
                return .init(attempt)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as MosaicAttemptJournalStore.Failure {
                throw Failure(failure)
            } catch {
                throw Failure.journalOperationFailed
            }
        }

        /// Loads and authenticates an existing journal without exposing its records.
        ///
        /// The key must be the same 256-bit field-derived key used to create this scope. A nonempty journal
        /// yields recovery authority. An authenticated empty journal yields exact-snapshot erasure authority
        /// because durable creation completed before any attempt record was appended.
        /// Call only during exclusive startup recovery, before retaining a fresh attempt for the same scope.
        @_spi(MosaicPrivateAlpha)
        public static func loadAuthenticatedRecovery(
            fieldDerivedJournalKey: SymmetricKey,
            scope: Scope,
            persistence: Persistence
        ) async throws -> LoadResult {
            do {
                let outcome = try await MosaicAttemptJournalStore
                    .authenticateExisting(
                    authenticationKey: fieldDerivedJournalKey,
                    scope: scope.journalScope,
                    persistence: persistence.journalPersistence
                )
                switch consume outcome {
                case let .abandonedFreshAttempt(authorization):
                    return .abandonedFreshAttempt(.init(authorization))
                case let .loadedRecovery(recovery):
                    return .loadedRecovery(.init(recovery))
                }
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as MosaicAttemptJournalStore.Failure {
                throw Failure(failure)
            } catch {
                throw Failure.journalOperationFailed
            }
        }

        /// Permanently abandons an unclaimed fresh attempt and returns the only proof that may erase it.
        ///
        /// A claimed, nonempty, recovered, broadcast-accepted, or completed attempt cannot reach this API.
        @_spi(MosaicPrivateAlpha)
        public static func abandonFreshAttempt(
            _ freshAttempt: consuming FreshAttempt
        ) async throws -> AttemptDisposition {
            do {
                return .init(
                    try await freshAttempt.authorizeAbandonment()
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as MosaicAttemptJournalStore.Failure {
                throw Failure(failure)
            } catch {
                throw Failure.journalOperationFailed
            }
        }

        /// Erases only the exact encrypted snapshot authorized by an abandoned-attempt disposition.
        ///
        /// The disposition is borrowed so a caller can retry after cancellation or a persistence failure.
        @_spi(MosaicPrivateAlpha)
        public static func eraseJournal(
            authorizedBy disposition: borrowing AttemptDisposition
        ) async throws {
            do {
                try await disposition.eraseJournal()
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as MosaicAttemptJournalStore.Failure {
                throw Failure(failure)
            } catch {
                throw Failure.journalOperationFailed
            }
        }
    }
}
#endif
