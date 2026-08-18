// OpalBase+Account+MosaicAttemptJournalCodec+ChainObservationDTO.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.MosaicAttemptJournalCodec {
    struct ChainObservationDTO: Codable {
        let transactionHash: Data
        let presenceKind: String
        let blockHash: Data?
        let confirmations: UInt32?

        init(_ observation: _OpalBase.Account.MosaicAttemptChainObservation) {
            transactionHash = observation.transactionHash.naturalOrder
            switch observation.presence {
            case let .present(valueBlockHash, valueConfirmations):
                presenceKind = "present"
                blockHash = valueBlockHash.map { Data($0) }
                confirmations = valueConfirmations
            case .authoritativeAbsence:
                presenceKind = "authoritativeAbsence"
                blockHash = nil
                confirmations = nil
            }
        }

        func makeValue() throws
            -> _OpalBase.Account.MosaicAttemptChainObservation {
            let hash = OpalBase.Transaction.Hash(
                naturalOrder: transactionHash
            )
            let presence: _OpalBase.Account.MosaicAttemptChainObservation
                .Presence
            switch presenceKind {
            case "present":
                guard let confirmations else {
                    throw Failure.decodingFailed
                }
                presence = .present(
                    blockHash: blockHash.map { Data($0) },
                    confirmations: confirmations
                )
            case "authoritativeAbsence":
                guard blockHash == nil, confirmations == nil else {
                    throw Failure.decodingFailed
                }
                presence = .authoritativeAbsence
            default:
                throw Failure.decodingFailed
            }
            guard let observation = _OpalBase.Account
                .MosaicAttemptChainObservation(
                    transactionHash: hash,
                    presence: presence
                ) else {
                throw Failure.decodingFailed
            }
            return observation
        }
    }
}
#endif
