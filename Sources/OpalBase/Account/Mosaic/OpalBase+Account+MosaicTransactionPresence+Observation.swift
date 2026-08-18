// OpalBase+Account+MosaicTransactionPresence+Observation.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.MosaicTransactionPresence {
    struct Observation: Sendable, Equatable {
        let transactionHash: OpalBase.Transaction.Hash
        let transactionBytes: Data
        let blockHash: Data?
        let confirmations: UInt32

        init?(
            transactionHash: OpalBase.Transaction.Hash,
            transactionBytes: Data,
            blockHash: Data?,
            confirmations: UInt32
        ) {
            guard transactionHash.naturalOrder.count
                    == OpalBase.Transaction.Hash.expectedByteCount,
                  !transactionBytes.isEmpty,
                  (confirmations == 0 && blockHash == nil)
                    || (confirmations > 0
                        && blockHash?.count
                            == OpalBase.Transaction.Hash.expectedByteCount)
            else {
                return nil
            }
            self.transactionHash = transactionHash
            self.transactionBytes = Data(transactionBytes)
            self.blockHash = blockHash.map { Data($0) }
            self.confirmations = confirmations
        }
    }
}
#endif
