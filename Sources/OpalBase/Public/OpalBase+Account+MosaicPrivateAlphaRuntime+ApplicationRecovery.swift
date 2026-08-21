// OpalBase+Account+MosaicPrivateAlphaRuntime+ApplicationRecovery.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// App-safe result of authenticating the Base journal and correlating any
    /// nonempty recovery with the exact opaque Fusion snapshot.
    @_spi(MosaicPrivateAlpha)
    public enum ApplicationRecoveryResult: ~Copyable, Sendable {
        /// An authenticated empty journal whose exact envelope is now authorized
        /// for application-owned outer cleanup.
        case abandonedFreshAttempt(
            OpalBase.Account.MosaicPrivateAlphaJournal.CleanupRequirement
        )

        /// The sole Base-owned session owner for an authenticated nonempty journal.
        case loadedSessionOwner(SessionOwner)
    }

    /// Authenticates and claims one restart recovery without returning journal
    /// values whose hidden storage contains OpalFusion types to the app target.
    @_spi(MosaicPrivateAlpha)
    public static func loadApplicationSessionRecovery(
        account: OpalBase.Account,
        binding: Binding,
        expectedWalletReservationIdentifier: UUID,
        expectedWalletGeneration: UInt64,
        transactionReader: OpalBase.Network.TransactionReader,
        fusionRecoverySnapshot: Data?,
        journalKey: OpalBase.Account.MosaicPrivateAlphaJournal.JournalKey,
        journalScope: OpalBase.Account.MosaicPrivateAlphaJournal.Scope,
        journalPersistence: OpalBase.Account.MosaicPrivateAlphaJournal.Persistence
    ) async throws -> ApplicationRecoveryResult {
        let loadResult = try await OpalBase.Account
            .MosaicPrivateAlphaJournal.loadAuthenticatedRecovery(
                fieldDerivedJournalKey: journalKey,
                scope: journalScope,
                persistence: journalPersistence
            )
        switch consume loadResult {
        case let .abandonedFreshAttempt(disposition):
            let requirement = try await OpalBase.Account
                .MosaicPrivateAlphaJournal.authorizeJournalErasure(
                    authorizedBy: disposition
                )
            return .abandonedFreshAttempt(requirement)
        case let .loadedRecovery(journalRecovery):
            guard let fusionRecoverySnapshot else {
                throw Failure.invalidRecoveryState
            }
            let owner = try await loadApplicationRecoverySessionOwner(
                account: account,
                binding: binding,
                expectedWalletReservationIdentifier:
                    expectedWalletReservationIdentifier,
                expectedWalletGeneration: expectedWalletGeneration,
                transactionReader: transactionReader,
                fusionRecoverySnapshot: fusionRecoverySnapshot,
                journalRecovery: journalRecovery
            )
            return .loadedSessionOwner(owner)
        }
    }
}
#endif
