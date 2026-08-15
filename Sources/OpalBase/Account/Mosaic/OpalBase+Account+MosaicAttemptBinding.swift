// OpalBase+Account+MosaicAttemptBinding.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Exact protocol-attempt identity persisted independently of wallet reservation identity.
    struct MosaicAttemptBinding: Sendable, Equatable {
        let attemptIdentifier: Data
        let generationIdentifier: Data
        let materialIdentifier: Data
        let walletReservationReference:
            OpalFusion.Host.MosaicReservationReference

        init?(
            attemptIdentifier: Data,
            generationIdentifier: Data,
            materialIdentifier: Data,
            walletReservationReference:
                OpalFusion.Host.MosaicReservationReference
        ) {
            let identityByteCount = 32
            guard attemptIdentifier.count == identityByteCount,
                  generationIdentifier.count == identityByteCount,
                  materialIdentifier.count == identityByteCount else {
                return nil
            }
            self.attemptIdentifier = Data(attemptIdentifier)
            self.generationIdentifier = Data(generationIdentifier)
            self.materialIdentifier = Data(materialIdentifier)
            self.walletReservationReference = walletReservationReference
        }

        var walletGeneration: UInt64 {
            walletReservationReference.generation
        }
    }
}
#endif
