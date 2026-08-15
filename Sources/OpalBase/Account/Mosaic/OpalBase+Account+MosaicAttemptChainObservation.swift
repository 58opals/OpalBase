// OpalBase+Account+MosaicAttemptChainObservation.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    /// One exact, normalized observation of the committed transaction on its bound chain.
    struct MosaicAttemptChainObservation: Sendable, Equatable {
        let transactionHash: OpalBase.Transaction.Hash
        let presence: Presence

        init?(
            transactionHash: OpalBase.Transaction.Hash,
            presence: Presence
        ) {
            guard transactionHash.naturalOrder.count
                    == OpalBase.Transaction.Hash.expectedByteCount else {
                return nil
            }
            switch presence {
            case let .present(blockHash, confirmations):
                guard (confirmations == 0 && blockHash == nil)
                        || (confirmations > 0
                            && blockHash?.count
                                == OpalBase.Transaction.Hash.expectedByteCount)
                else {
                    return nil
                }
            case .authoritativeAbsence:
                break
            }
            self.transactionHash = transactionHash
            self.presence = presence
        }
    }
}
#endif
