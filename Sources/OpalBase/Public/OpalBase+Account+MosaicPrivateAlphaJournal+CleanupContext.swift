// OpalBase+Account+MosaicPrivateAlphaJournal+CleanupContext.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Nonsecret exact binding between terminal cleanup and one encrypted journal envelope.
    ///
    /// The digest is SHA-256 over the complete encrypted envelope bytes. It contains no journal plaintext or
    /// key material and is intended for the app-owned terminal anchor, but it remains wallet-correlating
    /// metadata and must not be logged or transmitted.
    @_spi(MosaicPrivateAlpha)
    public struct CleanupContext: Equatable, Hashable, Sendable {
        @_spi(MosaicPrivateAlpha)
        public let scope: Scope

        @_spi(MosaicPrivateAlpha)
        public let expectedEnvelopeSHA256: Data

        /// Reconstructs a persisted cleanup context after validating its fixed-size SHA-256 digest.
        @_spi(MosaicPrivateAlpha)
        public init?(
            scope: Scope,
            expectedEnvelopeSHA256: Data
        ) {
            guard expectedEnvelopeSHA256.count == 32 else {
                return nil
            }
            self.scope = scope
            self.expectedEnvelopeSHA256 = Data(expectedEnvelopeSHA256)
        }

        init(
            validatedScope scope: Scope,
            expectedEnvelopeSHA256: Data
        ) {
            self.scope = scope
            self.expectedEnvelopeSHA256 = Data(expectedEnvelopeSHA256)
        }
    }
}
#endif
