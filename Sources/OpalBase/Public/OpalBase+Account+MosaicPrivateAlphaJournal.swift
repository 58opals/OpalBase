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

        /// Durably authorizes erasure of the exact abandoned-attempt envelope.
        ///
        /// A successful return means the app-owned persistence boundary committed its scope-bound terminal
        /// authorization and OpalBase discarded its retained codec, derived key, plaintext records, encrypted
        /// envelope, and persistence closures. It does not mean app-owned ciphertext, root or field-key
        /// material, or related private attempt artifacts were removed. The returned requirement must reach
        /// `completeJournalErasure(requiredBy:confirmOuterCleanup:)` before the app reports terminal cleanup.
        /// An authorization error or cancellation may occur after the marker commits; the disposition is
        /// borrowed so the caller can make the required idempotent retry or use durable read-back after restart.
        @_spi(MosaicPrivateAlpha)
        public static func authorizeJournalErasure(
            authorizedBy disposition: borrowing AttemptDisposition
        ) async throws -> CleanupRequirement {
            do {
                return .init(
                    try await disposition.authorizeJournalErasure()
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as MosaicAttemptJournalStore.Failure {
                throw Failure(failure)
            } catch {
                throw Failure.journalOperationFailed
            }
        }

        /// Loads cleanup authority from an app-owned durable terminal-erasure marker without a journal key.
        ///
        /// Returns `nil` for an absent or still-active journal. Call during exclusive startup recovery before
        /// deriving or loading the field journal key. A scope mismatch fails closed. The app must keep its
        /// durable marker authoritative until outer cleanup is confirmed or terminal completion is otherwise
        /// durably recorded by the application.
        @_spi(MosaicPrivateAlpha)
        public static func loadAuthorizedJournalCleanup(
            scope: Scope,
            persistence: Persistence
        ) async throws -> CleanupRequirement? {
            do {
                guard let requirement = try await MosaicAttemptJournalStore
                    .loadAuthorizedJournalCleanup(
                        scope: scope.journalScope,
                        persistence: persistence.journalPersistence
                    ) else {
                    return nil
                }
                return .init(requirement)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch let failure as MosaicAttemptJournalStore.Failure {
                throw Failure(failure)
            } catch {
                throw Failure.journalOperationFailed
            }
        }

        /// Completes journal erasure only after the application confirms all outer cleanup.
        ///
        /// The confirmation closure receives immutable scope and expected-envelope SHA-256 correlation. It
        /// must match that context against the app's durable terminal anchor, then durably remove and verify
        /// the absence of the encrypted envelope, field and root key material, salts, nonces, blind-request
        /// state, and related private attempt artifacts. It must throw if the context differs or any cleanup
        /// is incomplete or unverifiable. OpalBase cannot independently inspect those app-owned locations.
        /// Cancellation remains `CancellationError`; every other confirmation error maps to
        /// `Failure.outerCleanupIncomplete`. The requirement is borrowed so a caller can retry either outcome.
        @_spi(MosaicPrivateAlpha)
        public static func completeJournalErasure(
            requiredBy requirement: borrowing CleanupRequirement,
            confirmOuterCleanup: @Sendable (
                CleanupContext
            ) async throws -> Void
        ) async throws {
            do {
                try await requirement.confirmOuterCleanup(
                    using: confirmOuterCleanup
                )
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw Failure.outerCleanupIncomplete
            }
        }
    }
}
#endif
