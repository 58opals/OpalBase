// OpalBase+Account+MosaicPrivateAlphaJournal+Scope.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Stable, non-secret identity binding for one wallet-owned attempt journal.
    @_spi(MosaicPrivateAlpha)
    public struct Scope: Hashable, Sendable {
        @_spi(MosaicPrivateAlpha)
        public let walletIdentifier: UUID

        @_spi(MosaicPrivateAlpha)
        public let journalIdentifier: UUID

        @_spi(MosaicPrivateAlpha)
        public init(
            walletIdentifier: UUID,
            journalIdentifier: UUID
        ) {
            self.walletIdentifier = walletIdentifier
            self.journalIdentifier = journalIdentifier
        }

        init(
            journalScope: OpalBase.Account.MosaicAttemptJournalCodec.Scope
        ) {
            walletIdentifier = journalScope.walletIdentifier
            journalIdentifier = journalScope.journalIdentifier
        }

        var journalScope: OpalBase.Account.MosaicAttemptJournalCodec.Scope {
            .init(
                walletIdentifier: walletIdentifier,
                journalIdentifier: journalIdentifier
            )
        }
    }
}
#endif
