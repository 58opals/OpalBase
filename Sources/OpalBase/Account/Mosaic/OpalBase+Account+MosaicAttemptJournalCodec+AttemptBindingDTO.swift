// OpalBase+Account+MosaicAttemptJournalCodec+AttemptBindingDTO.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.MosaicAttemptJournalCodec {
    struct AttemptBindingDTO: Codable {
        let attemptIdentifier: Data
        let generationIdentifier: Data
        let materialIdentifier: Data
        let walletReservationReference: ReferenceDTO

        init(_ binding: _OpalBase.Account.MosaicAttemptBinding) {
            attemptIdentifier = binding.attemptIdentifier
            generationIdentifier = binding.generationIdentifier
            materialIdentifier = binding.materialIdentifier
            walletReservationReference = .init(
                binding.walletReservationReference
            )
        }

        func makeValue() throws -> _OpalBase.Account.MosaicAttemptBinding {
            guard let binding = _OpalBase.Account.MosaicAttemptBinding(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                materialIdentifier: materialIdentifier,
                walletReservationReference: try walletReservationReference
                    .makeValue()
            ) else {
                throw Failure.decodingFailed
            }
            return binding
        }
    }
}
#endif
