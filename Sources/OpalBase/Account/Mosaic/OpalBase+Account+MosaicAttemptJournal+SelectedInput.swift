// OpalBase+Account+MosaicAttemptJournal+SelectedInput.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.MosaicAttemptJournal {
    struct SelectedInput: Sendable, Equatable {
        let transactionHash: Data
        let outputIndex: UInt32
        let amountSatoshis: UInt64
        let lockingScript: Data

        init(_ input: OpalBase.Transaction.Output.Unspent) {
            transactionHash = input.previousTransactionHash.naturalOrder
            outputIndex = input.previousTransactionOutputIndex
            amountSatoshis = input.value
            lockingScript = input.lockingScript
        }
    }
}
#endif
