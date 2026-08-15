// OpalBase+Account+MosaicAttemptJournal+SelectedInput.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account.MosaicAttemptJournal {
    struct SelectedInput: Sendable, Equatable, Hashable {
        let transactionHash: Data
        let outputIndex: UInt32
        let amountSatoshis: UInt64
        let lockingScript: Data

        init(
            transactionHash: Data,
            outputIndex: UInt32,
            amountSatoshis: UInt64,
            lockingScript: Data
        ) {
            self.transactionHash = Data(transactionHash)
            self.outputIndex = outputIndex
            self.amountSatoshis = amountSatoshis
            self.lockingScript = Data(lockingScript)
        }

        init(_ input: OpalBase.Transaction.Output.Unspent) {
            self.init(
                transactionHash: input.previousTransactionHash.naturalOrder,
                outputIndex: input.previousTransactionOutputIndex,
                amountSatoshis: input.value,
                lockingScript: input.lockingScript
            )
        }
    }
}
#endif
