// OpalBase+Account+MosaicAttemptJournalCodec+TerminalDispositionDTO.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.MosaicAttemptJournalCodec {
    struct TerminalDispositionDTO: Codable {
        let kind: String
        let transactionHash: Data?
        let blockHash: Data?
        let confirmations: UInt32?

        init(_ disposition: _OpalBase.Account.MosaicAttemptTerminalDisposition) {
            switch disposition {
            case .walletReleased:
                kind = "walletReleased"
                transactionHash = nil
                blockHash = nil
                confirmations = nil
            case let .chainFinalized(hash, valueBlockHash, valueConfirmations):
                kind = "chainFinalized"
                transactionHash = hash.naturalOrder
                blockHash = Data(valueBlockHash)
                confirmations = valueConfirmations
            }
        }

        func makeValue() throws
            -> _OpalBase.Account.MosaicAttemptTerminalDisposition {
            switch kind {
            case "walletReleased":
                guard transactionHash == nil,
                      blockHash == nil,
                      confirmations == nil else {
                    throw Failure.decodingFailed
                }
                return .walletReleased
            case "chainFinalized":
                guard let transactionHash,
                      transactionHash.count
                        == OpalBase.Transaction.Hash.expectedByteCount,
                      let blockHash,
                      blockHash.count
                        == OpalBase.Transaction.Hash.expectedByteCount,
                      let confirmations,
                      confirmations > 0 else {
                    throw Failure.decodingFailed
                }
                return .chainFinalized(
                    transactionHash: .init(naturalOrder: transactionHash),
                    blockHash: blockHash,
                    confirmations: confirmations
                )
            default:
                throw Failure.decodingFailed
            }
        }
    }
}
#endif
