// OpalBase+Account+MosaicAttemptChainObservation+ConfirmedIdentity.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.MosaicAttemptChainObservation {
    struct ConfirmedIdentity: Sendable, Equatable {
        let blockHash: Data
        let confirmations: UInt32

        init(blockHash: Data, confirmations: UInt32) {
            self.blockHash = Data(blockHash)
            self.confirmations = confirmations
        }
    }

    var confirmedIdentity: ConfirmedIdentity? {
        guard case let .present(blockHash?, confirmations) = presence,
              confirmations > 0 else {
            return nil
        }
        return .init(blockHash: blockHash, confirmations: confirmations)
    }
}
#endif
