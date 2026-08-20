// OpalBase+Account+MosaicPrivateAlphaJournal+JournalKey.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Exact field-derived key material for one Mosaic journal scope.
    ///
    /// Derive this value for the journal field and scope before construction.
    /// Never pass a wallet master key or another reusable secret directly.
    @_spi(MosaicPrivateAlpha)
    public struct JournalKey: Sendable,
        CustomStringConvertible, CustomDebugStringConvertible {
        let encryptionKey: OpalCrypto.AuthenticatedEncryption.AES256GCM.Key

        /// Validates exact 32-byte field-derived journal key material.
        @_spi(MosaicPrivateAlpha)
        public init(fieldDerivedKeyMaterial: Data) throws {
            do {
                encryptionKey = try .init(
                    rawRepresentation: fieldDerivedKeyMaterial
                )
            } catch {
                throw Failure.invalidJournalKey
            }
        }

        /// A redacted description that never includes journal key material.
        @_spi(MosaicPrivateAlpha)
        public var description: String {
            "OpalBase.Account.MosaicPrivateAlphaJournal.JournalKey(redacted, byteCount: 32)"
        }

        /// A redacted debug description that never includes journal key material.
        @_spi(MosaicPrivateAlpha)
        public var debugDescription: String {
            description
        }
    }
}
#endif
